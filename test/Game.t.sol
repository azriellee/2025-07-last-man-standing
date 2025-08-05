// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Game} from "../src/Game.sol";

contract GameTest is Test {
    Game public game;

    address public deployer;
    address public player1;
    address public player2;
    address public player3;
    address public maliciousActor;

    // Initial game parameters for testing
    uint256 public constant INITIAL_CLAIM_FEE = 0.1 ether; // 0.1 ETH
    uint256 public constant GRACE_PERIOD = 1 days; // 1 day in seconds
    uint256 public constant FEE_INCREASE_PERCENTAGE = 10; // 10%
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5; // 5%

    // Events emitted
    event GameEnded(
        address indexed winner,
        uint256 prizeAmount,
        uint256 timestamp,
        uint256 round
    );

    function setUp() public {
        deployer = makeAddr("deployer");
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");
        maliciousActor = makeAddr("maliciousActor");

        vm.deal(deployer, 10 ether);
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(maliciousActor, 10 ether);

        vm.startPrank(deployer);
        game = new Game( 
            INITIAL_CLAIM_FEE,
            GRACE_PERIOD,
            FEE_INCREASE_PERCENTAGE,
            PLATFORM_FEE_PERCENTAGE
        );
        vm.stopPrank();
    }

    function testConstructor_RevertInvalidGracePeriod() public {
        vm.expectRevert("Game: Grace period must be greater than zero.");
        new Game(INITIAL_CLAIM_FEE, 0, FEE_INCREASE_PERCENTAGE, PLATFORM_FEE_PERCENTAGE);
    }

    function testPlayerClaimThrone() public {
        vm.startPrank(player1);
        vm.expectRevert("Game: Insufficient ETH sent to claim the throne.");
        game.claimThrone{value: INITIAL_CLAIM_FEE - 0.01 ether}();
        game.claimThrone{value: 1 ether}();
        vm.expectRevert("Game: You are already the king. No need to re-claim.");
        game.claimThrone{value: 1 ether}();

        assertEq(game.currentKing(), player1);
    }

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

    function testResetGame() public {
        vm.startPrank(player1);
        game.claimThrone{value: 1 ether}();
        vm.warp(block.timestamp + GRACE_PERIOD + 1 days);
        game.declareWinner();
        vm.stopPrank();

        vm.prank(deployer);
        game.resetGame();

        assertEq(game.currentKing(), address(0));
        assertEq(game.lastClaimTime(), block.timestamp);
        assertEq(game.pot(), 0);
        assertEq(game.gameEnded(), false);
    }
}