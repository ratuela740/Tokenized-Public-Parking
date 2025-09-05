;; Dynamic Pricing & Demand Management Contract
;; Automatically adjusts parking rates based on demand patterns and time-based rules

;; Error constants
(define-constant err-not-authorized (err u400))
(define-constant err-not-found (err u401))
(define-constant err-invalid-amount (err u402))
(define-constant err-invalid-time (err u403))
(define-constant err-pricing-disabled (err u404))
(define-constant err-invalid-multiplier (err u405))

;; Constants
(define-constant contract-owner tx-sender)
(define-constant max-price-multiplier u300) ;; 3x maximum
(define-constant min-price-multiplier u50)  ;; 0.5x minimum
(define-constant blocks-per-hour u144)      ;; Approximation

;; Data variables
(define-data-var pricing-enabled bool true)
(define-data-var default-peak-multiplier uint u150)  ;; 1.5x
(define-data-var default-offpeak-multiplier uint u80) ;; 0.8x

;; Time-based pricing rules for spaces
(define-map space-pricing-rules
  { space-id: uint }
  {
    owner: principal,
    base-rate: uint,
    peak-hours-start: uint,     ;; Block time for peak start (e.g., 8 AM)
    peak-hours-end: uint,       ;; Block time for peak end (e.g., 6 PM)
    peak-multiplier: uint,      ;; Price multiplier during peak (150 = 1.5x)
    offpeak-multiplier: uint,   ;; Price multiplier during off-peak (80 = 0.8x)
    dynamic-pricing-enabled: bool,
    last-updated: uint
  }
)

;; Demand tracking for spaces
(define-map space-demand-metrics
  { space-id: uint }
  {
    total-reservations: uint,
    peak-reservations: uint,
    offpeak-reservations: uint,
    average-duration: uint,
    last-reservation: uint,
    demand-score: uint          ;; 0-100 score based on booking frequency
  }
)

;; Hourly demand patterns (simplified to block ranges)
(define-map hourly-demand
  { space-id: uint, hour-block: uint }
  {
    reservation-count: uint,
    total-duration: uint,
    average-price: uint
  }
)

;; Price history tracking
(define-map price-history
  { space-id: uint, block-time: uint }
  {
    calculated-price: uint,
    demand-factor: uint,
    time-factor: uint
  }
)

;; Read-only functions
(define-read-only (get-space-pricing-rules (space-id uint))
  (map-get? space-pricing-rules { space-id: space-id })
)

(define-read-only (get-space-demand-metrics (space-id uint))
  (default-to
    {
      total-reservations: u0,
      peak-reservations: u0,
      offpeak-reservations: u0,
      average-duration: u0,
      last-reservation: u0,
      demand-score: u50
    }
    (map-get? space-demand-metrics { space-id: space-id })
  )
)

(define-read-only (get-current-price (space-id uint))
  (let
    (
      (pricing-rules (map-get? space-pricing-rules { space-id: space-id }))
    )
    (match pricing-rules
      rules (if (get dynamic-pricing-enabled rules)
              (calculate-dynamic-price space-id)
              (ok (get base-rate rules)))
      (ok u0)
    )
  )
)

(define-read-only (calculate-dynamic-price (space-id uint))
  (let
    (
      (rules (unwrap! (get-space-pricing-rules space-id) err-not-found))
      (demand-metrics (get-space-demand-metrics space-id))
      (current-block stacks-block-height)
      (is-peak-time (is-peak-hours space-id current-block))
      (demand-score (get demand-score demand-metrics))
      (base-rate (get base-rate rules))
      (time-multiplier (if is-peak-time 
                        (get peak-multiplier rules) 
                        (get offpeak-multiplier rules)))
      (demand-multiplier (+ u50 (/ demand-score u2))) ;; 50-100% based on demand
      (final-multiplier (min max-price-multiplier 
                            (max min-price-multiplier 
                                 (/ (* time-multiplier demand-multiplier) u100))))
      (dynamic-price (/ (* base-rate final-multiplier) u100))
    )
    (ok dynamic-price)
  )
)

(define-read-only (is-peak-hours (space-id uint) (current-block uint))
  (let
    (
      (rules (unwrap! (get-space-pricing-rules space-id) false))
      (peak-start (get peak-hours-start rules))
      (peak-end (get peak-hours-end rules))
      ;; Simplified: using block height modulo to simulate time of day
      (block-hour (mod current-block (* u24 blocks-per-hour)))
    )
    (and (>= block-hour peak-start) (<= block-hour peak-end))
  )
)

(define-read-only (get-pricing-status)
  (ok {
    pricing-enabled: (var-get pricing-enabled),
    default-peak-multiplier: (var-get default-peak-multiplier),
    default-offpeak-multiplier: (var-get default-offpeak-multiplier)
  })
)

;; Initialize pricing rules for a space
(define-public (setup-space-pricing (space-id uint) (base-rate uint) (peak-start uint) (peak-end uint))
  (let
    (
      (current-rules (map-get? space-pricing-rules { space-id: space-id }))
    )
    ;; Note: In full integration, we'd verify space ownership through main contract
    (asserts! (> base-rate u0) err-invalid-amount)
    (asserts! (< peak-start peak-end) err-invalid-time)
    (asserts! (< peak-end (* u24 blocks-per-hour)) err-invalid-time)
    
    (map-set space-pricing-rules
      { space-id: space-id }
      {
        owner: tx-sender,
        base-rate: base-rate,
        peak-hours-start: peak-start,
        peak-hours-end: peak-end,
        peak-multiplier: (var-get default-peak-multiplier),
        offpeak-multiplier: (var-get default-offpeak-multiplier),
        dynamic-pricing-enabled: true,
        last-updated: stacks-block-height
      }
    )
    
    ;; Initialize demand metrics if not exists
    (if (is-none (map-get? space-demand-metrics { space-id: space-id }))
      (map-set space-demand-metrics
        { space-id: space-id }
        {
          total-reservations: u0,
          peak-reservations: u0,
          offpeak-reservations: u0,
          average-duration: u0,
          last-reservation: u0,
          demand-score: u50
        }
      )
      true
    )
    
    (ok true)
  )
)

;; Update pricing multipliers for specific space
(define-public (update-space-multipliers (space-id uint) (peak-multiplier uint) (offpeak-multiplier uint))
  (let
    (
      (rules (unwrap! (get-space-pricing-rules space-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get owner rules)) err-not-authorized)
    (asserts! (<= peak-multiplier max-price-multiplier) err-invalid-multiplier)
    (asserts! (>= peak-multiplier min-price-multiplier) err-invalid-multiplier)
    (asserts! (<= offpeak-multiplier max-price-multiplier) err-invalid-multiplier)
    (asserts! (>= offpeak-multiplier min-price-multiplier) err-invalid-multiplier)
    
    (map-set space-pricing-rules
      { space-id: space-id }
      (merge rules {
        peak-multiplier: peak-multiplier,
        offpeak-multiplier: offpeak-multiplier,
        last-updated: stacks-block-height
      })
    )
    (ok true)
  )
)

;; Record reservation data for demand analysis
(define-public (record-reservation-demand (space-id uint) (duration-hours uint) (reservation-cost uint))
  (let
    (
      (current-metrics (get-space-demand-metrics space-id))
      (current-block stacks-block-height)
      (is-peak (is-peak-hours space-id current-block))
      (new-total-reservations (+ (get total-reservations current-metrics) u1))
      (new-peak-reservations (if is-peak 
                               (+ (get peak-reservations current-metrics) u1)
                               (get peak-reservations current-metrics)))
      (new-offpeak-reservations (if (not is-peak)
                                  (+ (get offpeak-reservations current-metrics) u1)
                                  (get offpeak-reservations current-metrics)))
      (new-average-duration (/ (+ (* (get average-duration current-metrics) 
                                    (get total-reservations current-metrics))
                                 duration-hours)
                              new-total-reservations))
      (new-demand-score (calculate-demand-score new-total-reservations new-peak-reservations))
    )
    
    (map-set space-demand-metrics
      { space-id: space-id }
      {
        total-reservations: new-total-reservations,
        peak-reservations: new-peak-reservations,
        offpeak-reservations: new-offpeak-reservations,
        average-duration: new-average-duration,
        last-reservation: current-block,
        demand-score: new-demand-score
      }
    )
    
    ;; Record price history
    (let
      (
        (current-price (unwrap! (get-current-price space-id) err-not-found))
      )
      (map-set price-history
        { space-id: space-id, block-time: current-block }
        {
          calculated-price: current-price,
          demand-factor: new-demand-score,
          time-factor: (if is-peak u150 u80)
        }
      )
    )
    
    (ok new-demand-score)
  )
)

;; Toggle dynamic pricing for a space
(define-public (toggle-dynamic-pricing (space-id uint) (enabled bool))
  (let
    (
      (rules (unwrap! (get-space-pricing-rules space-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get owner rules)) err-not-authorized)
    
    (map-set space-pricing-rules
      { space-id: space-id }
      (merge rules {
        dynamic-pricing-enabled: enabled,
        last-updated: stacks-block-height
      })
    )
    (ok true)
  )
)

;; Calculate demand score based on reservation patterns
(define-private (calculate-demand-score (total-reservations uint) (peak-reservations uint))
  (if (> total-reservations u0)
    (let
      (
        (peak-ratio (/ (* peak-reservations u100) total-reservations))
        (frequency-score (min u50 (/ total-reservations u2)))
        (peak-score (/ peak-ratio u2))
      )
      (min u100 (+ frequency-score peak-score))
    )
    u50
  )
)

;; Update system-wide pricing settings (owner only)
(define-public (update-default-multipliers (peak-multiplier uint) (offpeak-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (asserts! (<= peak-multiplier max-price-multiplier) err-invalid-multiplier)
    (asserts! (>= peak-multiplier min-price-multiplier) err-invalid-multiplier)
    (asserts! (<= offpeak-multiplier max-price-multiplier) err-invalid-multiplier)
    (asserts! (>= offpeak-multiplier min-price-multiplier) err-invalid-multiplier)
    
    (var-set default-peak-multiplier peak-multiplier)
    (var-set default-offpeak-multiplier offpeak-multiplier)
    (ok true)
  )
)

;; Enable/disable dynamic pricing system-wide
(define-public (toggle-pricing-system (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (var-set pricing-enabled enabled)
    (ok true)
  )
)

;; Helper function for minimum calculation
(define-private (min (a uint) (b uint))
  (if (< a b) a b)
)

;; Helper function for maximum calculation  
(define-private (max (a uint) (b uint))
  (if (> a b) a b)
)
