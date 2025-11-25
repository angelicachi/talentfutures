;; Talent Futures - Decentralized Income Share Agreement Protocol
;; A revolutionary platform for tokenizing future income streams

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-invalid-percentage (err u104))
(define-constant err-invalid-duration (err u105))
(define-constant err-isa-inactive (err u106))
(define-constant err-isa-completed (err u107))
(define-constant err-insufficient-funds (err u108))
(define-constant err-already-funded (err u109))
(define-constant err-payment-not-due (err u110))
(define-constant err-invalid-income (err u111))
(define-constant err-contract-paused (err u112))
(define-constant err-cap-reached (err u113))
(define-constant err-insufficient-balance (err u114))
(define-constant err-invalid-recipient (err u115))

;; Protocol parameters
(define-constant min-isa-amount u1000000000) ;; 1,000 STX minimum
(define-constant max-income-share u3000) ;; 30% maximum (basis points)
(define-constant min-duration u12) ;; 12 payment periods minimum
(define-constant max-duration u120) ;; 120 payment periods maximum (10 years)
(define-constant basis-points u10000) ;; 100% = 10000 basis points

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var platform-fee-bps uint u200) ;; 2% platform fee
(define-data-var total-isas-created uint u0)
(define-data-var total-funded uint u0)
(define-data-var total-repaid uint u0)
(define-data-var accumulated-fees uint u0)

;; Data Maps
(define-map income-share-agreements
  { talent: principal, isa-id: uint }
  {
    funding-amount: uint,
    income-share-bps: uint,
    duration-periods: uint,
    min-income-threshold: uint,
    max-repayment-cap: uint,
    total-raised: uint,
    total-repaid: uint,
    periods-completed: uint,
    created-at: uint,
    last-payment-at: uint,
    is-active: bool,
    is-completed: bool
  }
)

(define-map isa-investors
  { talent: principal, isa-id: uint, investor: principal }
  { amount-invested: uint, tokens-owned: uint }
)

(define-map isa-token-supply
  { talent: principal, isa-id: uint }
  uint
)

(define-map isa-token-balances
  { talent: principal, isa-id: uint, holder: principal }
  uint
)

(define-map talent-isa-count principal uint)

(define-map income-reports
  { talent: principal, isa-id: uint, period: uint }
  { reported-income: uint, payment-made: uint, reported-at: uint }
)

(define-map talent-stats
  principal
  { total-isas: uint, completed-isas: uint, total-raised: uint, total-repaid: uint }
)

;; Private Functions

(define-private (calculate-percentage (amount uint) (bps uint))
  (/ (* amount bps) basis-points)
)

(define-private (mint-isa-tokens (talent principal) (isa-id uint) (recipient principal) (amount uint))
  (let
    (
      (current-supply (default-to u0 (map-get? isa-token-supply { talent: talent, isa-id: isa-id })))
      (current-balance (default-to u0 (map-get? isa-token-balances { talent: talent, isa-id: isa-id, holder: recipient })))
    )
    (map-set isa-token-supply { talent: talent, isa-id: isa-id } (+ current-supply amount))
    (map-set isa-token-balances { talent: talent, isa-id: isa-id, holder: recipient } (+ current-balance amount))
    (ok true)
  )
)

(define-private (burn-isa-tokens (talent principal) (isa-id uint) (holder principal) (amount uint))
  (let
    (
      (current-supply (default-to u0 (map-get? isa-token-supply { talent: talent, isa-id: isa-id })))
      (current-balance (default-to u0 (map-get? isa-token-balances { talent: talent, isa-id: isa-id, holder: holder })))
    )
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (map-set isa-token-supply { talent: talent, isa-id: isa-id } (- current-supply amount))
    (map-set isa-token-balances { talent: talent, isa-id: isa-id, holder: holder } (- current-balance amount))
    (ok true)
  )
)

;; Read-Only Functions

(define-read-only (get-isa-details (talent principal) (isa-id uint))
  (map-get? income-share-agreements { talent: talent, isa-id: isa-id })
)

(define-read-only (get-investor-position (talent principal) (isa-id uint) (investor principal))
  (map-get? isa-investors { talent: talent, isa-id: isa-id, investor: investor })
)

(define-read-only (get-token-balance (talent principal) (isa-id uint) (holder principal))
  (ok (default-to u0 (map-get? isa-token-balances { talent: talent, isa-id: isa-id, holder: holder })))
)

(define-read-only (get-token-supply (talent principal) (isa-id uint))
  (ok (default-to u0 (map-get? isa-token-supply { talent: talent, isa-id: isa-id })))
)

(define-read-only (get-talent-isa-count (talent principal))
  (default-to u0 (map-get? talent-isa-count talent))
)

(define-read-only (get-income-report (talent principal) (isa-id uint) (period uint))
  (map-get? income-reports { talent: talent, isa-id: isa-id, period: period })
)

(define-read-only (get-talent-stats (talent principal))
  (map-get? talent-stats talent)
)

(define-read-only (calculate-payment-due (talent principal) (isa-id uint) (reported-income uint))
  (match (map-get? income-share-agreements { talent: talent, isa-id: isa-id })
    isa
    (let
      (
        (below-threshold (< reported-income (get min-income-threshold isa)))
        (payment-amount (if below-threshold
          u0
          (calculate-percentage reported-income (get income-share-bps isa))
        ))
        (remaining-cap (- (get max-repayment-cap isa) (get total-repaid isa)))
        (final-payment (if (< remaining-cap payment-amount) remaining-cap payment-amount))
      )
      (ok final-payment)
    )
    err-not-found
  )
)

(define-read-only (get-protocol-stats)
  {
    total-isas-created: (var-get total-isas-created),
    total-funded: (var-get total-funded),
    total-repaid: (var-get total-repaid),
    accumulated-fees: (var-get accumulated-fees),
    platform-fee-bps: (var-get platform-fee-bps),
    is-paused: (var-get contract-paused)
  }
)

;; Public Functions - ISA Creation & Management

(define-public (create-isa 
  (funding-amount uint)
  (income-share-bps uint)
  (duration-periods uint)
  (min-income-threshold uint)
  (max-repayment-cap uint))
  (let
    (
      (talent tx-sender)
      (current-count (get-talent-isa-count talent))
      (new-isa-id (+ current-count u1))
    )
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (>= funding-amount min-isa-amount) err-invalid-amount)
    (asserts! (and (> income-share-bps u0) (<= income-share-bps max-income-share)) err-invalid-percentage)
    (asserts! (and (>= duration-periods min-duration) (<= duration-periods max-duration)) err-invalid-duration)
    (asserts! (> max-repayment-cap funding-amount) err-invalid-amount)
    
    (map-set income-share-agreements
      { talent: talent, isa-id: new-isa-id }
      {
        funding-amount: funding-amount,
        income-share-bps: income-share-bps,
        duration-periods: duration-periods,
        min-income-threshold: min-income-threshold,
        max-repayment-cap: max-repayment-cap,
        total-raised: u0,
        total-repaid: u0,
        periods-completed: u0,
        created-at: stacks-block-height,
        last-payment-at: u0,
        is-active: true,
        is-completed: false
      }
    )
    
    (map-set talent-isa-count talent new-isa-id)
    (var-set total-isas-created (+ (var-get total-isas-created) u1))
    
    ;; Initialize or update talent stats
    (match (map-get? talent-stats talent)
      stats
      (map-set talent-stats talent
        (merge stats { total-isas: (+ (get total-isas stats) u1) })
      )
      (map-set talent-stats talent
        { total-isas: u1, completed-isas: u0, total-raised: u0, total-repaid: u0 }
      )
    )
    
    (ok new-isa-id)
  )
)

(define-public (fund-isa (talent principal) (isa-id uint) (amount uint))
  (let
    (
      (investor tx-sender)
      (isa (unwrap! (map-get? income-share-agreements { talent: talent, isa-id: isa-id }) err-not-found))
    )
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (get is-active isa) err-isa-inactive)
    (asserts! (not (get is-completed isa)) err-isa-completed)
    (asserts! (> amount u0) err-invalid-amount)
    
    (let
      (
        (new-total-raised (+ (get total-raised isa) amount))
        (funding-complete (>= new-total-raised (get funding-amount isa)))
      )
      (asserts! (<= new-total-raised (get funding-amount isa)) err-already-funded)
      
      ;; Transfer funds from investor to contract
      (try! (stx-transfer? amount investor (as-contract tx-sender)))
      
      ;; Update ISA
      (map-set income-share-agreements
        { talent: talent, isa-id: isa-id }
        (merge isa { total-raised: new-total-raised })
      )
      
      ;; Record investor position
      (match (map-get? isa-investors { talent: talent, isa-id: isa-id, investor: investor })
        existing
        (map-set isa-investors
          { talent: talent, isa-id: isa-id, investor: investor }
          {
            amount-invested: (+ (get amount-invested existing) amount),
            tokens-owned: (+ (get tokens-owned existing) amount)
          }
        )
        (map-set isa-investors
          { talent: talent, isa-id: isa-id, investor: investor }
          { amount-invested: amount, tokens-owned: amount }
        )
      )
      
      ;; Mint ISA tokens
      (unwrap! (mint-isa-tokens talent isa-id investor amount) err-invalid-amount)
      
      ;; Update stats
      (var-set total-funded (+ (var-get total-funded) amount))
      
      ;; Update talent stats
      (match (map-get? talent-stats talent)
        stats
        (map-set talent-stats talent
          (merge stats { total-raised: (+ (get total-raised stats) amount) })
        )
        true
      )
      
      ;; If fully funded, transfer to talent
      (if funding-complete
        (begin
          (try! (as-contract (stx-transfer? (get funding-amount isa) tx-sender talent)))
          (ok { funded: true, amount: amount })
        )
        (ok { funded: false, amount: amount })
      )
    )
  )
)

(define-public (report-income (isa-id uint) (reported-income uint))
  (let
    (
      (talent tx-sender)
      (isa (unwrap! (map-get? income-share-agreements { talent: talent, isa-id: isa-id }) err-not-found))
    )
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (get is-active isa) err-isa-inactive)
    (asserts! (not (get is-completed isa)) err-isa-completed)
    (asserts! (>= reported-income u0) err-invalid-income)
    
    (let
      (
        (current-period (+ (get periods-completed isa) u1))
      )
      (map-set income-reports
        { talent: talent, isa-id: isa-id, period: current-period }
        {
          reported-income: reported-income,
          payment-made: u0,
          reported-at: stacks-block-height
        }
      )
      
      (ok current-period)
    )
  )
)

(define-public (process-payment (talent principal) (isa-id uint))
  (let
    (
      (isa (unwrap! (map-get? income-share-agreements { talent: talent, isa-id: isa-id }) err-not-found))
      (current-period (+ (get periods-completed isa) u1))
      (income-report (unwrap! (map-get? income-reports { talent: talent, isa-id: isa-id, period: current-period }) err-payment-not-due))
    )
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (get is-active isa) err-isa-inactive)
    (asserts! (not (get is-completed isa)) err-isa-completed)
    (asserts! (is-eq (get payment-made income-report) u0) err-payment-not-due)
    
    (let
      (
        (reported-income (get reported-income income-report))
        (payment-due (unwrap! (calculate-payment-due talent isa-id reported-income) err-invalid-income))
        (platform-fee (calculate-percentage payment-due (var-get platform-fee-bps)))
        (investor-payment (- payment-due platform-fee))
        (new-total-repaid (+ (get total-repaid isa) payment-due))
        (cap-reached (>= new-total-repaid (get max-repayment-cap isa)))
        (duration-complete (>= current-period (get duration-periods isa)))
        (should-complete (or cap-reached duration-complete))
      )
      ;; Process payment if due
      (if (> payment-due u0)
        (begin
          ;; Transfer payment from talent
          (try! (stx-transfer? payment-due talent (as-contract tx-sender)))
          
          ;; Update accumulated fees
          (var-set accumulated-fees (+ (var-get accumulated-fees) platform-fee))
          
          ;; Update ISA
          (map-set income-share-agreements
            { talent: talent, isa-id: isa-id }
            (merge isa {
              total-repaid: new-total-repaid,
              periods-completed: current-period,
              last-payment-at: stacks-block-height,
              is-completed: should-complete,
              is-active: (not should-complete)
            })
          )
          
          ;; Update income report
          (map-set income-reports
            { talent: talent, isa-id: isa-id, period: current-period }
            (merge income-report { payment-made: payment-due })
          )
          
          ;; Update global stats
          (var-set total-repaid (+ (var-get total-repaid) payment-due))
          
          ;; Update talent stats
          (match (map-get? talent-stats talent)
            stats
            (map-set talent-stats talent
              (merge stats {
                total-repaid: (+ (get total-repaid stats) payment-due),
                completed-isas: (if should-complete (+ (get completed-isas stats) u1) (get completed-isas stats))
              })
            )
            true
          )
          
          (ok { payment: payment-due, completed: should-complete })
        )
        (begin
          ;; No payment due, just update period
          (map-set income-share-agreements
            { talent: talent, isa-id: isa-id }
            (merge isa {
              periods-completed: current-period,
              is-completed: duration-complete,
              is-active: (not duration-complete)
            })
          )
          
          (ok { payment: u0, completed: duration-complete })
        )
      )
    )
  )
)

;; Token Transfer Function
(define-public (transfer-tokens (talent principal) (isa-id uint) (amount uint) (recipient principal))
  (let
    (
      (sender tx-sender)
    )
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (not (is-eq sender recipient)) err-invalid-recipient)
    (asserts! (> amount u0) err-invalid-amount)
    
    (unwrap! (burn-isa-tokens talent isa-id sender amount) err-insufficient-balance)
    (unwrap! (mint-isa-tokens talent isa-id recipient amount) err-invalid-amount)
    
    ;; Update investor positions
    (match (map-get? isa-investors { talent: talent, isa-id: isa-id, investor: sender })
      sender-pos
      (map-set isa-investors
        { talent: talent, isa-id: isa-id, investor: sender }
        (merge sender-pos { tokens-owned: (- (get tokens-owned sender-pos) amount) })
      )
      true
    )
    
    (match (map-get? isa-investors { talent: talent, isa-id: isa-id, investor: recipient })
      recipient-pos
      (map-set isa-investors
        { talent: talent, isa-id: isa-id, investor: recipient }
        (merge recipient-pos { tokens-owned: (+ (get tokens-owned recipient-pos) amount) })
      )
      (map-set isa-investors
        { talent: talent, isa-id: isa-id, investor: recipient }
        { amount-invested: u0, tokens-owned: amount }
      )
    )
    
    (ok true)
  )
)

;; Admin Functions

(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

(define-public (update-platform-fee (new-fee-bps uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee-bps u1000) err-invalid-percentage) ;; Max 10%
    (var-set platform-fee-bps new-fee-bps)
    (ok new-fee-bps)
  )
)

(define-public (withdraw-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount (var-get accumulated-fees)) err-insufficient-funds)
    (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
    (var-set accumulated-fees (- (var-get accumulated-fees) amount))
    (ok amount)
  )
)