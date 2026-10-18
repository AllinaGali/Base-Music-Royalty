// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract AuraMusicRoyaltyHub {
    struct AudioTrack {
        address payable artist;
        uint256 streamPriceWei;
        uint256 licensePriceWei;
        uint256 totalStreams;
        bool isActive;
        bytes32 trackHash;
    }

    address payable public immutable hubAdmin;
    string public hubDescriptor;
    uint256 public platformFeeBps; // 250 = 2.5%
    uint256 public trackCounter;
    uint256 public accumulatedFees;
    bool public isHubPaused;

    mapping(address => bool) public approvedArtists;
    mapping(address => uint256) public artistEarnings;
    mapping(uint256 => AudioTrack) public tracks;

    event ArtistAdded(address indexed artist);
    event LicensePurchased(uint256 indexed trackId, address indexed buyer, uint256 price);
    event TrackCanceled(uint256 indexed trackId);
    event TreasuryDeposited(address indexed funder, uint256 amount);
    event ReservesDrained(address indexed admin, uint256 amount);
    event FeesHarvested(address indexed admin, uint256 amount);
    event TrackListed(uint256 indexed trackId, address indexed artist, uint256 streamPrice, uint256 licensePrice);
    event HubPauseToggled(bool isPaused);
    event ArtistRevoked(address indexed artist);
    event TrackStreamed(uint256 indexed trackId, address indexed listener, uint256 price);
    event DescriptorUpdated(string newDescriptor);
    event EarningsWithdrawn(address indexed artist, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == hubAdmin, "AuraMusic: Access denied");
        _;
    }

    modifier whenNotPaused() {
        require(!isHubPaused, "AuraMusic: Hub is paused");
        _;
    }

    constructor() {
        hubAdmin = payable(msg.sender);
        hubDescriptor = "Aura Base Music Royalty Hub v1";
        platformFeeBps = 250; // 2.5%
        isHubPaused = false;
        approvedArtists[msg.sender] = true;
    }

    // 1. addApprovedArtist
    function addApprovedArtist(address artist) external onlyAdmin {
        require(!approvedArtists[artist], "AuraMusic: Already approved");
        approvedArtists[artist] = true;
        emit ArtistAdded(artist);
    }

    // 2. buyCommercialLicense
    function buyCommercialLicense(uint256 trackId) external payable whenNotPaused {
        AudioTrack storage t = tracks[trackId];
        require(trackId > 0 && trackId <= trackCounter, "AuraMusic: Invalid ID");
        require(t.isActive, "AuraMusic: Track inactive");
        require(msg.value >= t.licensePriceWei, "AuraMusic: Insufficient payment");

        uint256 fee = (msg.value * platformFeeBps) / 10000;
        uint256 artistShare = msg.value - fee;

        accumulatedFees += fee;
        artistEarnings[t.artist] += artistShare;

        emit LicensePurchased(trackId, msg.sender, msg.value);
    }

    // 3. cancelTrackListing
    function cancelTrackListing(uint256 trackId) external {
        AudioTrack storage t = tracks[trackId];
        require(trackId > 0 && trackId <= trackCounter, "AuraMusic: Invalid ID");
        require(msg.sender == t.artist || msg.sender == hubAdmin, "AuraMusic: Unauthorized");
        require(t.isActive, "AuraMusic: Already inactive");

        t.isActive = false;
        emit TrackCanceled(trackId);
    }

    // 4. depositHubTreasury
    function depositHubTreasury() external payable whenNotPaused {
        require(msg.value > 0, "AuraMusic: Zero deposit");
        accumulatedFees += msg.value;
        emit TreasuryDeposited(msg.sender, msg.value);
    }

    // 5. drainHubReserves
    function drainHubReserves() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "AuraMusic: Zero balance");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: balance}("");
        require(sent, "AuraMusic: Sweep failed");

        emit ReservesDrained(hubAdmin, balance);
    }

    // 6. harvestPlatformFees
    function harvestPlatformFees() external onlyAdmin {
        uint256 amount = accumulatedFees;
        require(amount > 0, "AuraMusic: Zero fees");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: amount}("");
        require(sent, "AuraMusic: Harvest failed");

        emit FeesHarvested(hubAdmin, amount);
    }

    // 7. listNewAudioTrack
    function listNewAudioTrack(uint256 streamPrice, uint256 licensePrice, bytes32 trackHash) external whenNotPaused returns (uint256) {
        require(approvedArtists[msg.sender], "AuraMusic: Not an approved artist");
        require(streamPrice > 0 && licensePrice > streamPrice, "AuraMusic: Invalid pricing");

        trackCounter++;
        tracks[trackCounter] = AudioTrack({
            artist: payable(msg.sender),
            streamPriceWei: streamPrice,
            licensePriceWei: licensePrice,
            totalStreams: 0,
            isActive: true,
            trackHash: trackHash
        });

        emit TrackListed(trackCounter, msg.sender, streamPrice, licensePrice);
        return trackCounter;
    }

    // 8. pauseRoyaltyHub
    function pauseRoyaltyHub(bool isPaused) external onlyAdmin {
        isHubPaused = isPaused;
        emit HubPauseToggled(isPaused);
    }

    // 9. revokeArtistStatus
    function revokeArtistStatus(address artist) external onlyAdmin {
        require(approvedArtists[artist], "AuraMusic: Not an artist");
        require(artist != msg.sender, "AuraMusic: Cannot revoke self");
        approvedArtists[artist] = false;
        emit ArtistRevoked(artist);
    }

    // 10. streamAudioTrack
    function streamAudioTrack(uint256 trackId) external payable whenNotPaused {
        AudioTrack storage t = tracks[trackId];
        require(trackId > 0 && trackId <= trackCounter, "AuraMusic: Invalid ID");
        require(t.isActive, "AuraMusic: Track inactive");
        require(msg.value >= t.streamPriceWei, "AuraMusic: Insufficient payment");

        uint256 fee = (msg.value * platformFeeBps) / 10000;
        uint256 artistShare = msg.value - fee;

        accumulatedFees += fee;
        artistEarnings[t.artist] += artistShare;
        t.totalStreams++;

        emit TrackStreamed(trackId, msg.sender, msg.value);
    }

    // 11. updateHubDescriptor
    function updateHubDescriptor(string calldata newDescriptor) external onlyAdmin {
        require(bytes(newDescriptor).length > 0, "AuraMusic: Empty string");
        hubDescriptor = newDescriptor;
        emit DescriptorUpdated(newDescriptor);
    }

    // 12. withdrawArtistEarnings
    function withdrawArtistEarnings() external {
        uint256 amount = artistEarnings[msg.sender];
        require(amount > 0, "AuraMusic: Zero earnings");

        artistEarnings[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "AuraMusic: Withdrawal failed");

        emit EarningsWithdrawn(msg.sender, amount);
    }
}