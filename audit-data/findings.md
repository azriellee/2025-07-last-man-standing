1. compatible on any evm compatible chains, check if there are differences between chains that may not be compatible with certain functions
2. withdrawWinnings function does not follow CEI patterns, but has nonReentrant modifier so low/info i guess
3. sending more ether than claimFee will have no advantage, intended functionality? that would incentivise everyone to send msg.value == claimFee so the pot will never grow
4. claimThrone function's require check is wrong, resulting in no one ever being able to claimThrone

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
