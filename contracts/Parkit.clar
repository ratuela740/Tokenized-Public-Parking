(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-space-unavailable (err u104))
(define-constant err-reservation-expired (err u105))
(define-constant err-invalid-duration (err u106))
(define-constant err-unauthorized (err u107))
(define-constant err-already-reviewed (err u108))
(define-constant err-invalid-rating (err u109))
(define-constant err-review-not-allowed (err u110))

(define-fungible-token parkit-token)

(define-data-var total-spaces uint u0)
(define-data-var reservation-counter uint u0)
(define-data-var token-price uint u1000000)
(define-data-var platform-fee uint u50000)
(define-data-var review-counter uint u0)

(define-map parking-spaces
  { space-id: uint }
  {
    owner: principal,
    location: (string-ascii 100),
    hourly-rate: uint,
    is-available: bool,
    created-at: uint,
    average-rating: uint,
    total-reviews: uint
  }
)

(define-map reservations
  { reservation-id: uint }
  {
    space-id: uint,
    renter: principal,
    start-time: uint,
    end-time: uint,
    total-cost: uint,
    is-active: bool,
    tokens-earned: uint
  }
)

(define-map user-stats
  { user: principal }
  {
    total-reservations: uint,
    total-spent: uint,
    tokens-earned: uint,
    spaces-owned: uint
  }
)

(define-map space-earnings
  { space-id: uint }
  { total-earned: uint, total-hours: uint }
)

(define-map reviews
  { review-id: uint }
  {
    space-id: uint,
    reviewer: principal,
    reservation-id: uint,
    rating: uint,
    comment: (string-ascii 500),
    created-at: uint,
    is-verified: bool
  }
)

(define-map user-reviews
  { user: principal, space-id: uint }
  { review-id: uint, has-reviewed: bool }
)

(define-map space-ratings
  { space-id: uint }
  {
    total-rating-points: uint,
    total-reviews: uint,
    five-star: uint,
    four-star: uint,
    three-star: uint,
    two-star: uint,
    one-star: uint
  }
)

(define-read-only (get-parking-space (space-id uint))
  (map-get? parking-spaces { space-id: space-id })
)

(define-read-only (get-reservation (reservation-id uint))
  (map-get? reservations { reservation-id: reservation-id })
)

(define-read-only (get-user-stats (user principal))
  (default-to
    { total-reservations: u0, total-spent: u0, tokens-earned: u0, spaces-owned: u0 }
    (map-get? user-stats { user: user })
  )
)

(define-read-only (get-space-earnings (space-id uint))
  (default-to
    { total-earned: u0, total-hours: u0 }
    (map-get? space-earnings { space-id: space-id })
  )
)

(define-read-only (get-review (review-id uint))
  (map-get? reviews { review-id: review-id })
)

(define-read-only (get-space-ratings (space-id uint))
  (default-to
    { total-rating-points: u0, total-reviews: u0, five-star: u0, four-star: u0, three-star: u0, two-star: u0, one-star: u0 }
    (map-get? space-ratings { space-id: space-id })
  )
)

(define-read-only (get-user-review-status (user principal) (space-id uint))
  (default-to
    { review-id: u0, has-reviewed: false }
    (map-get? user-reviews { user: user, space-id: space-id })
  )
)

(define-read-only (get-average-rating (space-id uint))
  (let ((ratings (get-space-ratings space-id)))
    (if (> (get total-reviews ratings) u0)
      (/ (get total-rating-points ratings) (get total-reviews ratings))
      u0
    )
  )
)

(define-read-only (get-total-spaces)
  (var-get total-spaces)
)

(define-read-only (get-token-balance (user principal))
  (ft-get-balance parkit-token user)
)

(define-read-only (calculate-cost (hourly-rate uint) (duration-hours uint))
  (* hourly-rate duration-hours)
)

(define-read-only (calculate-tokens-earned (cost uint))
  (/ cost (var-get token-price))
)

(define-read-only (is-space-available (space-id uint) (start-time uint) (end-time uint))
  (let ((space (unwrap! (get-parking-space space-id) false)))
    (and
      (get is-available space)
    ;;   (not ((true) space-id start-time end-time))
    )
  )
)


(define-private (check-reservation-conflict (params (list 4 uint)) (has-conflict bool))
  (let ((space-id (unwrap-panic (element-at params u0)))
        (start-time (unwrap-panic (element-at params u1)))
        (end-time (unwrap-panic (element-at params u2))))
    has-conflict
  )
)

(define-public (add-parking-space (location (string-ascii 100)) (hourly-rate uint))
  (let ((space-id (+ (var-get total-spaces) u1)))
    (asserts! (> hourly-rate u0) err-invalid-duration)
    (map-set parking-spaces
      { space-id: space-id }
      {
        owner: tx-sender,
        location: location,
        hourly-rate: hourly-rate,
        is-available: true,
        created-at: stacks-block-height,
        average-rating: u0,
        total-reviews: u0
      }
    )
    (var-set total-spaces space-id)
    (let ((current-stats (get-user-stats tx-sender)))
      (map-set user-stats
        { user: tx-sender }
        (merge current-stats { spaces-owned: (+ (get spaces-owned current-stats) u1) })
      )
    )
    (ok space-id)
  )
)

(define-public (update-space-availability (space-id uint) (available bool))
  (let ((space (unwrap! (get-parking-space space-id) err-not-found)))
    (asserts! (is-eq tx-sender (get owner space)) err-unauthorized)
    (map-set parking-spaces
      { space-id: space-id }
      (merge space { is-available: available })
    )
    (ok true)
  )
)

(define-public (reserve-space (space-id uint) (duration-hours uint))
  (let (
    (space (unwrap! (get-parking-space space-id) err-not-found))
    (reservation-id (+ (var-get reservation-counter) u1))
    (start-time stacks-block-height)
    (end-time (+ stacks-block-height (* duration-hours u144)))
    (total-cost (calculate-cost (get hourly-rate space) duration-hours))
    (platform-cost (+ total-cost (var-get platform-fee)))
    (tokens-earned (calculate-tokens-earned total-cost))
  )
    (asserts! (> duration-hours u0) err-invalid-duration)
    (asserts! (get is-available space) err-space-unavailable)
    (asserts! (is-space-available space-id start-time end-time) err-space-unavailable)
    
    (try! (stx-transfer? platform-cost tx-sender (get owner space)))
    
    (map-set reservations
      { reservation-id: reservation-id }
      {
        space-id: space-id,
        renter: tx-sender,
        start-time: start-time,
        end-time: end-time,
        total-cost: total-cost,
        is-active: true,
        tokens-earned: tokens-earned
      }
    )
    
    (var-set reservation-counter reservation-id)
    
    (try! (ft-mint? parkit-token tokens-earned tx-sender))
    
    (let ((current-stats (get-user-stats tx-sender)))
      (map-set user-stats
        { user: tx-sender }
        (merge current-stats {
          total-reservations: (+ (get total-reservations current-stats) u1),
          total-spent: (+ (get total-spent current-stats) platform-cost),
          tokens-earned: (+ (get tokens-earned current-stats) tokens-earned)
        })
      )
    )
    
    (let ((current-earnings (get-space-earnings space-id)))
      (map-set space-earnings
        { space-id: space-id }
        {
          total-earned: (+ (get total-earned current-earnings) total-cost),
          total-hours: (+ (get total-hours current-earnings) duration-hours)
        }
      )
    )
    
    (ok reservation-id)
  )
)

(define-public (end-reservation (reservation-id uint))
  (let ((reservation (unwrap! (get-reservation reservation-id) err-not-found)))
    (asserts! (or 
      (is-eq tx-sender (get renter reservation))
      (> stacks-block-height (get end-time reservation))
    ) err-unauthorized)
    
    (map-set reservations
      { reservation-id: reservation-id }
      (merge reservation { is-active: false })
    )
    (ok true)
  )
)

(define-public (extend-reservation (reservation-id uint) (additional-hours uint))
  (let (
    (reservation (unwrap! (get-reservation reservation-id) err-not-found))
    (space (unwrap! (get-parking-space (get space-id reservation)) err-not-found))
    (additional-cost (calculate-cost (get hourly-rate space) additional-hours))
    (platform-cost (+ additional-cost (var-get platform-fee)))
    (additional-tokens (calculate-tokens-earned additional-cost))
    (new-end-time (+ (get end-time reservation) (* additional-hours u144)))
  )
    (asserts! (is-eq tx-sender (get renter reservation)) err-unauthorized)
    (asserts! (get is-active reservation) err-reservation-expired)
    (asserts! (> additional-hours u0) err-invalid-duration)
    
    (try! (stx-transfer? platform-cost tx-sender (get owner space)))
    
    (map-set reservations
      { reservation-id: reservation-id }
      (merge reservation {
        end-time: new-end-time,
        total-cost: (+ (get total-cost reservation) additional-cost),
        tokens-earned: (+ (get tokens-earned reservation) additional-tokens)
      })
    )
    
    (try! (ft-mint? parkit-token additional-tokens tx-sender))
    
    (let ((current-stats (get-user-stats tx-sender)))
      (map-set user-stats
        { user: tx-sender }
        (merge current-stats {
          total-spent: (+ (get total-spent current-stats) platform-cost),
          tokens-earned: (+ (get tokens-earned current-stats) additional-tokens)
        })
      )
    )
    
    (ok true)
  )
)

(define-public (update-token-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-price u0) err-invalid-duration)
    (var-set token-price new-price)
    (ok true)
  )
)

(define-public (update-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set platform-fee new-fee)
    (ok true)
  )
)

(define-public (withdraw-platform-fees)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let ((balance (stx-get-balance (as-contract tx-sender))))
      (and (> balance u0)
        (try! (as-contract (stx-transfer? balance tx-sender contract-owner)))
      )
      (ok balance)
    )
  )
)

(define-public (burn-tokens (amount uint))
  (ft-burn? parkit-token amount tx-sender)
)

(define-private (update-star-count (rating uint) (current-ratings (tuple (total-rating-points uint) (total-reviews uint) (five-star uint) (four-star uint) (three-star uint) (two-star uint) (one-star uint))))
  (if (is-eq rating u5)
    (merge current-ratings { five-star: (+ (get five-star current-ratings) u1) })
    (if (is-eq rating u4)
      (merge current-ratings { four-star: (+ (get four-star current-ratings) u1) })
      (if (is-eq rating u3)
        (merge current-ratings { three-star: (+ (get three-star current-ratings) u1) })
        (if (is-eq rating u2)
          (merge current-ratings { two-star: (+ (get two-star current-ratings) u1) })
          (merge current-ratings { one-star: (+ (get one-star current-ratings) u1) })
        )
      )
    )
  )
)

(define-private (can-review-space (user principal) (space-id uint) (reservation-id uint))
  (let ((reservation (unwrap! (get-reservation reservation-id) false)))
    (and
      (is-eq (get renter reservation) user)
      (is-eq (get space-id reservation) space-id)
      (not (get is-active reservation))
      (not (get has-reviewed (get-user-review-status user space-id)))
    )
  )
)

(define-public (submit-review (space-id uint) (reservation-id uint) (rating uint) (comment (string-ascii 500)))
  (let (
    (review-id (+ (var-get review-counter) u1))
    (space (unwrap! (get-parking-space space-id) err-not-found))
    (reservation (unwrap! (get-reservation reservation-id) err-not-found))
    (current-ratings (get-space-ratings space-id))
    (review-status (get-user-review-status tx-sender space-id))
  )
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
    (asserts! (not (get has-reviewed review-status)) err-already-reviewed)
    (asserts! (can-review-space tx-sender space-id reservation-id) err-review-not-allowed)
    
    (map-set reviews
      { review-id: review-id }
      {
        space-id: space-id,
        reviewer: tx-sender,
        reservation-id: reservation-id,
        rating: rating,
        comment: comment,
        created-at: stacks-block-height,
        is-verified: true
      }
    )
    
    (map-set user-reviews
      { user: tx-sender, space-id: space-id }
      { review-id: review-id, has-reviewed: true }
    )
    
    (let ((updated-ratings (update-star-count rating current-ratings)))
      (map-set space-ratings
        { space-id: space-id }
        (merge updated-ratings {
          total-rating-points: (+ (get total-rating-points updated-ratings) rating),
          total-reviews: (+ (get total-reviews updated-ratings) u1)
        })
      )
    )
    
    (let ((new-average (get-average-rating space-id)))
      (map-set parking-spaces
        { space-id: space-id }
        (merge space {
          average-rating: new-average,
          total-reviews: (+ (get total-reviews space) u1)
        })
      )
    )
    
    (var-set review-counter review-id)
    (ok review-id)
  )
)

(define-public (get-space-reviews (space-id uint) (offset uint) (limit uint))
  (let ((max-reviews (if (> limit u20) u20 limit)))
    (ok {
      space-id: space-id,
      total-reviews: (get total-reviews (get-space-ratings space-id)),
      average-rating: (get-average-rating space-id),
      rating-breakdown: (get-space-ratings space-id)
    })
  )
)

(define-public (flag-review (review-id uint) (reason (string-ascii 200)))
  (let ((review (unwrap! (get-review review-id) err-not-found)))
    (asserts! (not (is-eq tx-sender (get reviewer review))) err-unauthorized)
    (ok true)
  )
)

(define-public (get-top-rated-spaces (limit uint))
  (ok {
    message: "top-rated-spaces-query",
    limit: (if (> limit u50) u50 limit)
  })
)

(define-public (moderate-review (review-id uint) (action (string-ascii 20)))
  (let ((review (unwrap! (get-review review-id) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (or (is-eq action "approve") (is-eq action "reject")) err-invalid-rating)
    
    (map-set reviews
      { review-id: review-id }
      (merge review { is-verified: (is-eq action "approve") })
    )
    (ok true)
  )
)

(define-read-only (get-review-summary (space-id uint))
  (let ((ratings (get-space-ratings space-id)))
    {
      space-id: space-id,
      average-rating: (get-average-rating space-id),
      total-reviews: (get total-reviews ratings),
      rating-distribution: {
        five-star: (get five-star ratings),
        four-star: (get four-star ratings),
        three-star: (get three-star ratings),
        two-star: (get two-star ratings),
        one-star: (get one-star ratings)
      }
    }
  )
)

(define-read-only (get-contract-info)
  {
    total-spaces: (var-get total-spaces),
    total-reservations: (var-get reservation-counter),
    total-reviews: (var-get review-counter),
    token-price: (var-get token-price),
    platform-fee: (var-get platform-fee),
    contract-owner: contract-owner
  }
)
