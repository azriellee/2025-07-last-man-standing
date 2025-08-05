1. compatible on any evm compatible chains, check if there are differences between chains that may not be compatible with certain functions
2. withdrawWinnings function does not follow CEI patterns, but has nonReentrant modifier so low/info i guess
3. sending more ether than claimFee will have no advantage, intended functionality? that would incentivise everyone to send msg.value == claimFee so the pot will never grow
4. claimThrone function's require check is wrong, resulting in no one ever being able to claimThrone
5. event emitted in declareWinner function not correct due to update of pot value

# Root + Impact

## Description

- Players are supposed to be able to call `claimThrone` function upon creation of the contract to claim the title of `currentKing`.

- Due to an error in the require statement, the function requires the caller to be the `currentKing`'s address, rather than ensuring that the caller and the `currentKing` are different addresses. Since the `currentKing` is initialised to 0 address, the require statement will never pass.

```solidity
function claimThrone() external payable gameNotEnded nonReentrant {
        require(msg.value >= claimFee, "Game: Insufficient ETH sent to claim the throne.");
@>        require(msg.sender == currentKing, "Game: You are already the king. No need to re-claim.");
```

## Risk

**Likelihood**: High

- This function will definitely be called by players and is integral to the operation of the contract.

**Impact**: High

- There are adverse impacts as it would cause all functionality to not work and the entire contract would not be able to be used.

## Proof of Concept

By creating a simple test code to try and call `claimThrone`, the function reverts.

```solidity
    function testPlayerClaimThrone() public {
        vm.startPrank(player1);
        game.claimThrone{value: 1 ether}();

        assertEq(game.currentKing(), player1);
    }
```

## Recommended Mitigation

Amending the erroneous require check would solve the issue.

```diff
    function claimThrone() external payable gameNotEnded nonReentrant {
        require(msg.value >= claimFee, "Game: Insufficient ETH sent to claim the throne.");
-        require(msg.sender == currentKing, "Game: You are already the king. No need to re-claim.");
+        require(msg.sender != currentKing, "Game: You are already the king. No need to re-claim.");
```

# Root + Impact

## Description

- When the `declareWinner` function is called, the event that should be emitted should correspond to the following:

```solidity
    /**
     * @dev Emitted when the game ends and a winner is declared.
     * @param winner The address of the declared winner.
     * @param prizeAmount The total prize amount won.
     * @param timestamp The block timestamp when the winner was declared.
     * @param round The game round that just ended.
     */
    event GameEnded(
        address indexed winner,
        uint256 prizeAmount,
        uint256 timestamp,
        uint256 round
    );
```

- However due to incorrect usage of `pot` value, the `prizeAmount` emitted will always be 0 since and will not correctly tie to the total prize amount won

```solidity
    function declareWinner() external gameNotEnded {
        require(currentKing != address(0), "Game: No one has claimed the throne yet.");
        require(
            block.timestamp > lastClaimTime + gracePeriod,
            "Game: Grace period has not expired yet."
        );

        gameEnded = true;

        pendingWinnings[currentKing] = pendingWinnings[currentKing] + pot;
@>        pot = 0; // Reset pot after assigning to winner's pending winnings

@>        emit GameEnded(currentKing, pot, block.timestamp, gameRound); // Pot value just reset, will be 0
    }
```

## Risk

**Likelihood**: High

- This will always occur when the `declareWinner` function is called, which is a core functionality of the contract.

**Impact**: Medium

- The incorrect values emitted may cause confusion for users or front-end applications that rely on event tracking. This may break some of the functionality of applications that require accurate event values being emitted.

## Proof of Concept

The following test code fails due to the logs being different

```solidity
    function testDeclareWinner() public {
        vm.startPrank(player1);
        vm.expectRevert("Game: No one has claimed the throne yet.");
        game.declareWinner();

        game.claimThrone{value: 1 ether}();
        vm.expectRevert("Game: Grace period has not expired yet.");
        game.declareWinner();

        vm.warp(block.timestamp + GRACE_PERIOD + 1 days);
        vm.expectEmit(true, true, false, true);
        emit GameEnded(player1, game.pot(), block.timestamp, 1);
        game.declareWinner();
        vm.stopPrank();

        uint256 winnings = game.pendingWinnings(player1);
        assertEq(winnings, 0.95 ether);
        assertEq(game.gameEnded(), true);
    }
```

## Recommended Mitigation

The value of the current prize amount should be saved before resetting the pot to 0, and this value should then be used instead.

```diff
function declareWinner() external gameNotEnded {
    require(currentKing != address(0), "Game: No one has claimed the throne yet.");
    require(
        block.timestamp > lastClaimTime + gracePeriod,
        "Game: Grace period has not expired yet."
    );

    gameEnded = true;
+    uint256 prizeAmount = pot; // Store pot value before resetting
    pendingWinnings[currentKing] = pendingWinnings[currentKing] + prizeAmount;
    pot = 0; // Reset pot after assigning to winner's pending winnings
-    emit GameEnded(currentKing, pot, block.timestamp, gameRound);
+    emit GameEnded(currentKing, prizeAmount, block.timestamp, gameRound);
}
```

# Root + Impact

## Description

* `withdrawWinnings` function should follow CEI pattern, however it transfers ether before updating the value of `pendingWinnings` to 0. This exposes the function to re-entrancy risks and is not a secure withdraw pattern as opposed to what it states in the comments

```solidity
    /**
     * @dev Allows the declared winner to withdraw their prize.
     * Uses a secure withdraw pattern with a manual reentrancy guard.
     */
    function withdrawWinnings() external nonReentrant {
        uint256 amount = pendingWinnings[msg.sender];
        require(amount > 0, "Game: No winnings to withdraw.");

@>        (bool success, ) = payable(msg.sender).call{value: amount}(""); // interactions called first to transfer ether to msg.sender
        require(success, "Game: Failed to withdraw winnings.");

@>        pendingWinnings[msg.sender] = 0; // then the pendingWinnings is zeroed out

        emit WinningsWithdrawn(msg.sender, amount);
    }
```

## Risk

**Likelihood**: Low

* The function is protected by a `nonReentrant` modifier as well, so the risk of re-entrancy attacks are low. But the function would solely rely on the modifier for protection.
  
**Impact**: High

* If the manual re-entrancy guard could be bypassed, there is a potential for the entire contract to be drained.


## Proof of Concept

NA

## Recommended Mitigation

This could be easily solved by bringing the update of pending winnings forward before the transfer call.

```diff
    function withdrawWinnings() external nonReentrant {
        uint256 amount = pendingWinnings[msg.sender];
        require(amount > 0, "Game: No winnings to withdraw.");

+        pendingWinnings[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Game: Failed to withdraw winnings.");

-        pendingWinnings[msg.sender] = 0;

        emit WinningsWithdrawn(msg.sender, amount);
    }
```
