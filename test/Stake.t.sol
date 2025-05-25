pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
// import {TaccToken} from "../src/Token.sol";
import {Factory} from "../src/FactoryStaking.sol";
import {Test, console} from "forge-std/Test.sol";
import {TaccStaking} from "../src/Staking.sol";
import {MockV3Aggregator} from "lib/chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {PriceConverter} from "../src/PriceConverter.sol";

contract StakeTest is Test, Script {
    Factory factory;
    TaccStaking staking;
    MockV3Aggregator priceFeed;
    ERC20Mock public token;
    ERC20Mock public foreignToken; // Added for foreign token tests
    //  PriceConverter priceConverter;
    address User1 = makeAddr("User1");
    address User2 = makeAddr("User2");
    address OwnerAddress = makeAddr("Owner");
    address FeeCollector = makeAddr("FeeCollector");

    // Events for testing
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    function setUp() public {
        factory = new Factory();
        token = new ERC20Mock();
        foreignToken = new ERC20Mock(); // Initialize foreign token
        // priceFeed = new MockV3Aggregator(
        //     18,
        //     653
        //  );
        //   priceConverter = new PriceConverter(address(priceFeed))
        staking = new TaccStaking(
            address(token),
            address(token),
            //  0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526,
            OwnerAddress,
            60,
            100,
            10
        );

        vm.startPrank(msg.sender);
        token.mint(User1, 10000 ether);
        token.mint(User2, 10000 ether);
        token.mint(address(staking), 100000 ether);
        foreignToken.mint(address(staking), 5000 ether); // Mint foreign tokens to contract
        vm.stopPrank();

        //  vm.startPrank(User1);
        //    token.approve(address(staking), type(uint256).max);
        //  vm.stopPrank();

        //   vm.startPrank(User2);
        //    token.approve(address(staking), type(uint256).max);
        //  vm.stopPrank();

        vm.deal(User1, 1 ether);
        vm.deal(User2, 1 ether);
        //  hoax(User2, 1 ether);
    }

    modifier onlyStartReward() {
        vm.prank(staking.owner());
        staking.startReward();
        _;
    }

    // ========== EXISTING TESTS (PRESERVED) ==========

    function testPriceOfBNB() external {
        uint256 priceOfBNB = staking.getPriceofBNB();
        console.log("Price of BNB:", priceOfBNB);
    }

    function testDeposit() external onlyStartReward {
        uint256 UserStartTokenBalance = token.balanceOf(User1);
        uint256 UserStartEtherBalance = address(User1).balance;

        console.log("Start Token Balance:", UserStartTokenBalance);
        console.log("Start ETH Balance:", UserStartEtherBalance);

        // Prank as User1 and give them enough ETH
        vm.deal(User1, 1 ether);
        vm.startPrank(User1);

        // Approve staking contract to spend User1's tokens
        token.approve(address(staking), type(uint256).max);

        // Get price of BNB in USD (wei/USD)
        uint256 price = staking.getPriceofBNB(); // e.g., 651573585340000000000

        // Calculate $0.50 worth of BNB in wei
        uint256 fee = (0.5e18 * 1e18) / price; // = $0.50 * 1e18 / price

        // Optional: add a buffer to prevent rounding issues
        fee += 1e12;

        console.log("Calculated fee in wei:", fee);
        console.log("BNB/USD price:", price);

        // Deposit with correct fee
        staking.deposit{value: fee}(1000 ether);

        vm.stopPrank();

        uint256 UserEndTokenBalance = token.balanceOf(User1);
        uint256 UserEndEtherBalance = address(User1).balance;

        console.log("End Token Balance:", UserEndTokenBalance);
        console.log("End ETH Balance:", UserEndEtherBalance);
        assertLt(UserEndTokenBalance, UserStartTokenBalance, "Token balance should decrease after deposit");
    }

    function testWithdraw() external onlyStartReward {
        // Fund User1 with ETH and Tokens
        deal(address(token), User1, 1000 ether);
        deal(User1, 1 ether);

        // Prank as User1
        vm.startPrank(User1);

        // Approve and deposit first
        token.approve(address(staking), type(uint256).max);
        staking.deposit{value: staking.getAmountOfFeeInBNB()}(1000 ether);
        console.log("staking.lockDuration():", staking.lockDuration());

        // Simulate time passing to allow withdrawal
        skip(30); // 30 seconds

        uint256 startTokenBalance = token.balanceOf(User1);
        uint256 startETHBalance = User1.balance;

        console.log("Start Token Balance:", startTokenBalance);
        console.log("Start ETH Balance:", startETHBalance);
        console.log("Staking contract staked amount:", staking.totalStaked());

        uint256 userPendingReward = staking.pendingReward(User1);
        console.log("pendingReward after 30 secs:", userPendingReward);

        // Simulate time passing to allow withdrawal again
        skip(30); // 30 + 30 => 1 minute
        uint256 userPendingReward2 = staking.pendingReward(User1);
        console.log("pendingReward after 60 secs:", userPendingReward2);
        skip(staking.lockDuration()); // 60 + 60
        uint256 userPendingReward3 = staking.pendingReward(User1);
        console.log("pendingReward after 120 secs:", userPendingReward3);

        // Withdraw (will return both staked + rewards)
        staking.withdraw{value: staking.getAmountOfFeeInBNB()}(0); // amount ignored inside function

        uint256 endTokenBalance = token.balanceOf(User1);
        uint256 endETHBalance = User1.balance;

        console.log("End Token Balance:", endTokenBalance);
        console.log("End ETH Balance:", endETHBalance);

        assertGt(endTokenBalance, startTokenBalance, "Token balance should increase after withdrawal");
        assertLt(endETHBalance, startETHBalance, "ETH balance should decrease due to fee payment");

        vm.stopPrank();
    }

    function testEmergencyWithdraw() external {
        // Start impersonating User1
        vm.startPrank(User1);

        uint256 depositAmount = 1000 ether;
        token.approve(address(staking), type(uint256).max);
        staking.deposit{value: staking.getAmountOfFeeInBNB()}(depositAmount);

        (uint256 stakedBalanceBefore,,,) = staking.userInfo(User1);
        uint256 userTokenBalanceBefore = token.balanceOf(User1);

        // emergencyWithdraw called inside the same prank session, no new startPrank needed
        staking.emergencyWithdraw();

        (uint256 stakedBalanceAfter,,,) = staking.userInfo(User1);
        uint256 userTokenBalanceAfter = token.balanceOf(User1);

        assertEq(stakedBalanceAfter, 0, "User staking amount should be zero after emergencyWithdraw");
        assertGt(
            userTokenBalanceAfter, userTokenBalanceBefore, "User token balance should increase after emergencyWithdraw"
        );

        uint256 unlockTime = staking.holderUnlockTime(User1);
        assertEq(unlockTime, 0, "Unlock time should be reset to zero");

        vm.stopPrank();
    }

    // ========== NEW COMPREHENSIVE TESTS ==========

    function testConstructorInitialization() external {
        assertEq(address(staking.stakingToken()), address(token));
        assertEq(address(staking.rewardToken()), address(token));
        assertEq(staking.feeCollector(), OwnerAddress);
        assertEq(staking.lockDuration(), 60);
        assertEq(staking.apy(), 100);
        assertEq(staking.exitPenaltyPerc(), 10);
        assertEq(staking.fixedUsdFee(), 0.5 * 10 ** 18);

        // Check pool info
        (, uint256 allocPoint, uint256 lastRewardTimestamp, uint256 accTokensPerShare) = staking.poolInfo(0);
        // assertEq(lpToken, address(token));
        assertEq(allocPoint, 1000);
        assertEq(lastRewardTimestamp, 21616747);
        assertEq(accTokensPerShare, 0);
    }

    function testStartRewardOnlyOnce() external {
        vm.startPrank(staking.owner());
        staking.startReward();

        vm.expectRevert("Can only start rewards once");
        staking.startReward();
        vm.stopPrank();
    }

    function testStartRewardOnlyOwner() external {
        vm.prank(User1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.startReward();
    }

    function testStopReward() external onlyStartReward {
        vm.prank(staking.owner());
        staking.stopReward();

        assertEq(staking.apy(), 0);
    }

    function testStopRewardOnlyOwner() external {
        vm.prank(User1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.stopReward();
    }

    function testDepositInsufficientFee() external onlyStartReward {
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), 1000 ether);

        vm.expectRevert("Insufficient fee");
        staking.deposit{value: fee - 1}(1000 ether);
        vm.stopPrank();
    }

    function testDepositZeroAmount() external onlyStartReward {
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        staking.deposit{value: fee}(0);

        (uint256 amount,,,) = staking.userInfo(User1);
        assertEq(amount, 0);
        vm.stopPrank();
    }

    function testDepositWithExistingStake() external onlyStartReward {
        uint256 depositAmount = 500 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount * 2);

        // First deposit
        staking.deposit{value: fee}(depositAmount);

        // Second deposit
        vm.deal(User1, 1 ether); // Refill ETH for second fee
        staking.deposit{value: fee}(depositAmount);

        (uint256 amount,,,) = staking.userInfo(User1);
        assertEq(amount, depositAmount * 2);
        vm.stopPrank();
    }

    function testDepositEvent() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit Deposit(User1, depositAmount);

        staking.deposit{value: fee}(depositAmount);
        vm.stopPrank();
    }

    function testWithdrawEarly() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        vm.deal(User1, 1 ether); // Refill for withdraw fee
        vm.expectRevert("May not do normal withdraw early");
        staking.withdraw{value: fee}(0);
        vm.stopPrank();
    }

    function testWithdrawInsufficientFee() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        skip(staking.lockDuration() + 1);

        vm.expectRevert("Insufficient fee");
        staking.withdraw{value: fee - 1}(0);
        vm.stopPrank();
    }

    function testWithdrawEvent() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        skip(staking.lockDuration() + 1);
        vm.deal(User1, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(User1, depositAmount);

        staking.withdraw{value: fee}(0);
        vm.stopPrank();
    }

    function testEmergencyWithdrawEvent() external {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();
        uint256 expectedAmount = depositAmount - (depositAmount * 10 / 100); // 10% penalty

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(User1, expectedAmount);

        staking.emergencyWithdraw();
        vm.stopPrank();
    }

    function testEmergencyWithdrawAfterLockPeriod() external {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        skip(staking.lockDuration() + 1);

        uint256 balanceBefore = token.balanceOf(User1);
        staking.emergencyWithdraw();
        uint256 balanceAfter = token.balanceOf(User1);

        // No penalty after lock period
        assertEq(balanceAfter - balanceBefore, depositAmount);
        vm.stopPrank();
    }

    function testPendingRewardBeforeStart() external {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        assertEq(staking.pendingReward(User1), 0);
        vm.stopPrank();
    }

    function testPendingRewardAfterMaxRewardTime() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);

        // Wait beyond max reward time
        skip(staking.lockDuration() + 30);

        uint256 pending1 = staking.pendingReward(User1);

        // Wait more time
        skip(30);
        uint256 pending2 = staking.pendingReward(User1);

        // Rewards should not increase after max reward time
        assertEq(pending1, pending2);
        vm.stopPrank();
    }

    function testUpdateApy() external {
        uint256 newApy = 200;

        vm.prank(staking.owner());
        staking.updateApy(newApy);

        assertEq(staking.apy(), newApy);
    }

    function testUpdateApyTooHigh() external {
        vm.prank(staking.owner());
        vm.expectRevert("APY must be below 10000%");
        staking.updateApy(10001);
    }

    function testUpdateApyOnlyOwner() external {
        vm.prank(User1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.updateApy(200);
    }

    function testUpdateLockDuration() external {
        uint256 newDuration = 120;

        vm.prank(staking.owner());
        staking.updatelockduration(newDuration);

        assertEq(staking.lockDuration(), newDuration);
    }

    function testUpdateLockDurationTooHigh() external {
        vm.prank(staking.owner());
        vm.expectRevert("Duration must be below 4 weeks");
        staking.updatelockduration(4838401);
    }

    function testUpdateExitPenalty() external {
        uint256 newPenalty = 20;

        vm.prank(staking.owner());
        staking.updateExitPenalty(newPenalty);

        assertEq(staking.exitPenaltyPerc(), newPenalty);
    }

    function testUpdateExitPenaltyTooHigh() external {
        vm.prank(staking.owner());
        vm.expectRevert("May not set higher than 30%");
        staking.updateExitPenalty(31);
    }

    function testSetFeeCollector() external {
        vm.prank(staking.owner());
        staking.setFeeCollector(FeeCollector);

        assertEq(staking.feeCollector(), FeeCollector);
    }

    function testSetFeeCollectorZeroAddress() external {
        vm.prank(staking.owner());
        vm.expectRevert(); // Should revert with InvalidAddress error
        staking.setFeeCollector(address(0));
    }

    function testSetFees() external {
        uint256 newFee = 1 * 1e18;

        vm.prank(staking.owner());
        staking.setFees(newFee);

        assertEq(staking.fixedUsdFee(), newFee);
    }

    function testEmergencyWithdrawR() external {
        uint256 withdrawAmount = 1000 ether;
        uint256 balanceBefore = token.balanceOf(staking.owner());

        vm.prank(staking.owner());
        staking.emergencyWithdrawR(withdrawAmount);

        assertEq(token.balanceOf(staking.owner()), balanceBefore + withdrawAmount);
    }

    // function testEmergencyWithdrawRTooMuch() external onlyStartReward {
    //     // First stake some tokens to reduce available rewards
    //     uint256 depositAmount = 50000 ether;
    //     uint256 fee = staking.getAmountOfFeeInBNB();

    //     vm.startPrank(User1);
    //     token.approve(address(staking), depositAmount);
    //     staking.deposit{value: fee}(depositAmount);
    //     vm.stopPrank();

    //     uint256 availableRewards = staking.rewardsRemaining();

    //     vm.prank(staking.owner());
    //     vm.expectRevert("not enough tokens to take out");
    //     staking.emergencyWithdrawR(availableRewards + 1);
    // }

    function testClearForeignToken() external {
        uint256 foreignBalance = foreignToken.balanceOf(address(staking));
        uint256 ownerBalanceBefore = foreignToken.balanceOf(staking.owner());

        vm.prank(staking.owner());
        staking.clearforeignToken(address(foreignToken), 0);

        assertEq(foreignToken.balanceOf(staking.owner()), ownerBalanceBefore + foreignBalance);
        assertEq(foreignToken.balanceOf(address(staking)), 0);
    }

    function testClearForeignTokenSpecificAmount() external {
        uint256 withdrawAmount = 1000 ether;
        uint256 ownerBalanceBefore = foreignToken.balanceOf(staking.owner());

        vm.prank(staking.owner());
        staking.clearforeignToken(address(foreignToken), withdrawAmount);

        assertEq(foreignToken.balanceOf(staking.owner()), ownerBalanceBefore + withdrawAmount);
    }

    function testClearForeignTokenRewardToken() external {
        vm.prank(staking.owner());
        vm.expectRevert("Cannot withdraw reward token");
        staking.clearforeignToken(address(token), 0);
    }

    function testCalculateNewRewards() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);
        vm.stopPrank();

        skip(1 days);

        uint256 expectedReward = (1 days * depositAmount * 100) / (100 * 365 days);
        uint256 actualReward = staking.calculateNewRewards();

        assertApproxEqRel(actualReward, expectedReward, 1e16); // 1% tolerance
    }

    function testRewardsRemaining() external {
        uint256 totalRewards = token.balanceOf(address(staking));
        assertEq(staking.rewardsRemaining(), totalRewards);
    }

    function testGetUserRewardInfo() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);
        vm.stopPrank();

        (uint256 stakeTimestamp, uint256 maxRewardTime, uint256 unlockTime, bool canEarnRewards) =
            staking.getUserRewardInfo(User1);

        assertEq(stakeTimestamp, block.timestamp);
        assertEq(maxRewardTime, block.timestamp + 60);
        assertEq(unlockTime, block.timestamp + 60);
        assertTrue(canEarnRewards);

        // After max reward time
        skip(staking.lockDuration() + 1);
        (,,, canEarnRewards) = staking.getUserRewardInfo(User1);
        assertFalse(canEarnRewards);
    }

    function testMassUpdatePools() external {
        vm.prank(staking.owner());
        staking.massUpdatePools();
        // Should not revert
    }

    function testMultipleUsersStaking() external onlyStartReward {
        uint256 depositAmount = 1000 ether;
        uint256 fee = staking.getAmountOfFeeInBNB();

        // User1 stakes
        vm.startPrank(User1);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);
        vm.stopPrank();

        // User2 stakes
        vm.startPrank(User2);
        token.approve(address(staking), depositAmount);
        staking.deposit{value: fee}(depositAmount);
        vm.stopPrank();

        assertEq(staking.totalStaked(), depositAmount * 2);

        (uint256 amount1,,,) = staking.userInfo(User1);
        (uint256 amount2,,,) = staking.userInfo(User2);

        assertEq(amount1, depositAmount);
        assertEq(amount2, depositAmount);
    }

    function testReceiveFunction() external {
        uint256 amount = 0.1 ether;
        (bool success,) = address(staking).call{value: amount}("");
        assertTrue(success);
        assertEq(address(staking).balance, amount);
    }

    // Fuzz tests
    function testFuzzDeposit(uint256 amount) external onlyStartReward {
        vm.assume(amount > 0 && amount <= 5000 ether);

        uint256 fee = staking.getAmountOfFeeInBNB();

        vm.startPrank(User1);
        token.approve(address(staking), amount);
        staking.deposit{value: fee}(amount);

        (uint256 userAmount,,,) = staking.userInfo(User1);
        assertEq(userAmount, amount);
        vm.stopPrank();
    }

    function testFuzzUpdateApy(uint256 newApy) external {
        vm.assume(newApy <= 10000);

        vm.prank(staking.owner());
        staking.updateApy(newApy);

        assertEq(staking.apy(), newApy);
    }

    function testFuzzUpdateLockDuration(uint256 newDuration) external {
        vm.assume(newDuration <= 4838400);

        vm.prank(staking.owner());
        staking.updatelockduration(newDuration);

        assertEq(staking.lockDuration(), newDuration);
    }

    function testFuzzUpdateExitPenalty(uint256 newPenalty) external {
        vm.assume(newPenalty <= 30);

        vm.prank(staking.owner());
        staking.updateExitPenalty(newPenalty);

        assertEq(staking.exitPenaltyPerc(), newPenalty);
    }
}
