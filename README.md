# Cross-chain Rebase Token

1. A prototocol that allows users to deposit into a vault, and in return, recieves rebase tokens that represent their underlying balance.
2. Rebase token - balanceOf is dynamic to show changing balance with time.
    - Balance changes linearly with time.
    - Mint tokens to our users every time they perform an action (such as minting, burning, transferring or bridging).
3. Interest rate 
    - Individually set an interest rate for each user based on a global interest rate of the protocol at the time the user deposits into the value.
    - This global interest rate can only decrease to incentivise and reward early adopters.
    - Increase token adoption
    - For example, user 1 deposits ETH at an early stage and their interest rate is set to 0.05, which is the global interest rate at that time. User 2 comes along a year later, when the global interest rate has dropped to 0.04, and is therefore set an individual interest rate of 0.04.
    - The individuals will keep the interest rate they were given initially, regardless of future interest rate drops.
