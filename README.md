# 🅿️ Parkit - Tokenized Public Parking

> 🚗 Reserve, pay, and track space usage with blockchain technology

## 🌟 Overview

Parkit is a decentralized parking management system built on the Stacks blockchain. It allows users to tokenize parking spaces, make reservations, and earn rewards through our native token system.

## ✨ Features

- 🏗️ **Space Management**: Add and manage parking spaces
- 📅 **Reservations**: Book parking spaces for specific durations  
- 💰 **Token Rewards**: Earn PARKIT tokens for each reservation
- 📊 **Analytics**: Track earnings and usage statistics
- ⚡ **Real-time Availability**: Check space availability instantly
- 🔒 **Secure Payments**: Blockchain-based payment processing

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Stacks CLI](https://docs.stacks.co/docs/cli) configured

### Installation

1. Clone the repository
```bash
git clone https://github.com/yourusername/parkit.git
cd parkit
```

2. Install dependencies
```bash
npm install
```

3. Run tests
```bash
clarinet test
```

## 📖 Usage

### For Space Owners 🏢

#### Add a Parking Space
```clarity
(contract-call? .Parkit add-parking-space "Downtown Main St" u500000)
```

#### Update Space Availability
```clarity
(contract-call? .Parkit update-space-availability u1 true)
```

### For Renters 🚗

#### Reserve a Space
```clarity
(contract-call? .Parkit reserve-space u1 u4)
```

#### Extend Reservation
```clarity
(contract-call? .Parkit extend-reservation u1 u2)
```

#### End Reservation Early
```clarity
(contract-call? .Parkit end-reservation u1)
```

### Read-Only Functions 📊

#### Get Space Information
```clarity
(contract-call? .Parkit get-parking-space u1)
```

#### Check User Statistics
```clarity
(contract-call? .Parkit get-user-stats 'SP1234567890)
```

#### Get Token Balance
```clarity
(contract-call? .Parkit get-token-balance 'SP1234567890)
```

## 💎 Token Economics

- **PARKIT Token**: Earned for each reservation made
- **Exchange Rate**: Configurable (default: 1 STX = 1 PARKIT)
- **Platform Fee**: Small fee per transaction (configurable)
- **Burning**: Users can burn tokens if desired

## 🔧 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `add-parking-space` | Add a new parking space | location, hourly-rate |
| `reserve-space` | Reserve a parking space | space-id, duration-hours |
| `extend-reservation` | Extend existing reservation | reservation-id, additional-hours |
| `end-reservation` | End reservation early | reservation-id |
| `update-space-availability` | Toggle space availability | space-id, available |

### Read-Only Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `get-parking-space` | Get space details | space-id |
| `get-reservation` | Get reservation details | reservation-id |
| `get-user-stats` | Get user statistics | user-principal |
| `is-space-available` | Check availability | space-id, start-time, end-time |

## 🎯 Example Workflow

1. **Space Owner** adds a parking space at $5/hour
2. **Renter** reserves the space for 4 hours
3. **Payment** of 20 STX + platform fee is transferred
4. **Tokens** are minted and awarded to the renter
5. **Reservation** becomes active and trackable
6. **Statistics** are updated for both parties

## 🛡️ Security Features

- Owner-only functions for sensitive operations
- Input validation on all parameters
- Reservation conflict checking
- Secure payment processing
- Error handling with descriptive codes

## 📈 Analytics

Track your parking business with built-in analytics:

- Total spaces owned
- Revenue generated
- Hours booked
- Token rewards earned
- Reservation history

## 🤝 Contributing

We welcome contributions! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/docs/clarity/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet)

