// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TakoyakiPresale is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    //===============================================//
    //          Contract Variables                   //
    //===============================================//

    // Start time 03/01/2021 @ 9:00pm (GMT) //
    uint256 public constant PRESALE_START_TIME = 1614632400;

    // Start time 03/02/2021 @ 9:00pm (GMT) //
    uint256 public constant PRESALE_END_TIME = 1614715200;

    uint256 public constant DECIMAL_MULTIPLIER = 10**18;

    //Minimum contribution is 1 BNB
    uint256 public constant MIN_CONTRIBUTION = 1 * DECIMAL_MULTIPLIER;

    //Maximum contribution is 15 BNB
    uint256 public constant MAX_CONTRIBUTION = 15 * DECIMAL_MULTIPLIER;

    //The presale amount to be collected is 100k JLP
    uint256 public constant PRESALE_CAP = 100000 * DECIMAL_MULTIPLIER;

    // Wallet contributions state
    mapping(address => uint256) private _walletContributions;

    // Claimable Takoyakis state
    mapping(address => uint256) private _claimableTakoyakis;

    bool private _tokensClaimable = false;

    // Total BNB raised
    uint256 public bnbRaised;

    // Total JLP sold
    uint256 public TakoyakisSold;

    // Pointer to the TakoyakiToken
    IBEP20 public TakoyakiToken;

    // How many Takoyakis do we send per BNB contributed.
    uint256 public TakoyakisPerBnb;

    //===============================================//
    //                 Constructor                   //
    //===============================================//
    constructor(IBEP20 _TakoyakiToken, uint256 _TakoyakisPerBnb)
        public
        Ownable()
    {
        TakoyakiToken = _TakoyakiToken;
        TakoyakisPerBnb = _TakoyakisPerBnb;
    }

    //===============================================//
    //                   Events                      //
    //===============================================//
    event TokenPurchase(
        address indexed beneficiary,
        uint256 bnbAmount,
        uint256 tokenAmount
    );

    event TokenClaim(address indexed beneficiary, uint256 tokenAmount);

    //===============================================//
    //                   Methods                     //
    //===============================================//

    // BUY TOKENS

    /**
     * Main entry point for buying into the Pre-Sale. Contract Receives BNB
     */
    function purchaseTokens() external payable {
        // Validations.
        require(
            msg.sender != address(0),
            "TakoyakiPresale: beneficiary is the zero address."
        );

        require(isOpen() == true, "TakoyakiPresale: the presale is not open.");

        // Check if we will sell more than the PRESALE_CAP
        require(
            TakoyakisSold.add(_getTokenAmount(msg.value)) <= PRESALE_CAP,
            "TakoyakiPresale: the presale amount is reached."
        );

        uint256 userContribution =
            _walletContributions[msg.sender].add(msg.value);
        require(
            userContribution >= MIN_CONTRIBUTION,
            "TakoyakiPresale: minimum contribution is 1 BNB."
        );
        require(
            userContribution <= MAX_CONTRIBUTION,
            "TakoyakiPresale: You cannot buy more than 15 BNB worth of tokens."
        );

        // Validations passed, buy tokens
        _buyTokens(msg.sender, msg.value);
    }

    /**
     * Function that perform the actual transfer of JLPs
     */
    function _buyTokens(address beneficiary, uint256 bnbAmount) internal {
        // Update how much bnb we have raised
        bnbRaised = bnbRaised.add(bnbAmount);

        // Update how much bnb has this address contributed
        _walletContributions[beneficiary] = _walletContributions[beneficiary]
            .add(bnbAmount);

        // Calculate how many JLPs can be bought with that bnb amount
        uint256 tokenAmount = _getTokenAmount(bnbAmount);

        // Update how much JLP we sold
        TakoyakisSold = TakoyakisSold.add(tokenAmount);

        _claimableTakoyakis[beneficiary] = _claimableTakoyakis[beneficiary].add(
            tokenAmount
        );

        emit TokenPurchase(beneficiary, bnbAmount, tokenAmount);
    }

    // CLAIM TOKENS

    /**
     * Function that handles the retrieval of purchased tokens, if the sender is eligible to.
     * To be called only after the tokens are set to be claimable by the owner.
     */
    function claimTokens() external {
        // Validations.
        require(
            msg.sender != address(0),
            "TakoyakiPresale: beneficiary is the zero address"
        );

        require(
            areTokensClaimable() == true,
            "TakoyakiPresale: The tokens are not claimable yet."
        );
        require(
            _claimableTakoyakis[msg.sender] > 0,
            "TakoyakiPresale: There is nothing to claim."
        );

        // Send tokens to user and update user's state
        _claimTokens(msg.sender);
    }

    /**
     * Function that sends the JLPs to the beneficiary and updates the user's state.
     */
    function _claimTokens(address beneficiary) internal {
        // Transfer the JLP tokens to the beneficiary
        uint256 tokenAmount = _claimableTakoyakis[beneficiary];
        _claimableTakoyakis[beneficiary] = 0;
        TakoyakiToken.safeTransfer(beneficiary, tokenAmount);

        emit TokenClaim(beneficiary, tokenAmount);
    }

    /**
     * Calculate how many JLPs do they get given the amount of BNB.
     */
    function _getTokenAmount(uint256 bnbAmount)
        internal
        view
        returns (uint256)
    {
        return bnbAmount.mul(TakoyakisPerBnb);
    }

    /**
     * Get claimable JLP tokens for address
     */
    function getClaimableTakoyakisAmount(address user)
        public
        view
        returns (uint256)
    {
        return _claimableTakoyakis[user];
    }

    /**
     * Get wallet contributions in BNB for address
     */
    function getBNBContributedAmount(address user)
        public
        view
        returns (uint256)
    {
        return _walletContributions[user];
    }

    // CONTROL FUNCTIONS

    // The presale is open if the transaction made is within the time interval
    function isOpen() public view returns (bool) {
        return now >= PRESALE_START_TIME && now <= PRESALE_END_TIME;
    }

    // Are tokens claimable?
    function areTokensClaimable() public view returns (bool) {
        return _tokensClaimable;
    }

    // Enable retrieval of the tokens. This function will be called by the contract owner once the presale is finished
    // and liquidity is provided in the Liquidity pools.
    function enableTokenRetrieval() public onlyOwner {
        _tokensClaimable = true;
    }

    // Allow the owner to retrieve the remaining tokens
    function takeOutRemainingTokens() public onlyOwner {
        TakoyakiToken.safeTransfer(
            msg.sender,
            TakoyakiToken.balanceOf(address(this))
        );
    }

    // Allow the owner to retrieve the raised funds
    function takeOutFundingRaised() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
