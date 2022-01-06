// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//@author Nethny [TIIK]
/*
	This contract allows you to transfer NFT RMRK
	to the MOVR network, assigning to the specified
	owner specified in the RMRK messages
	in the Kusama network.
	This contract does not implement the full
	functionality of the RMRK NFT, but allows
	you to transfer ownership rights to NFT,
	which allows them to be used in the MOVR ecosystem

	Warning: ERC721 has been changed!
*/
contract Hub is ERC721, Ownable {
    using Counters for Counters.Counter;

    constructor() ERC721("Dublicate_RMRK", "DRMRK") {}

    Counters.Counter private _tokenIdCounter;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI query for nonexistent token"
        );

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI)
        internal
        virtual
    {
        require(
            _exists(tokenId),
            "ERC721URIStorage: URI set of nonexistent token"
        );
        _tokenURIs[tokenId] = _tokenURI;
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
    }

    //ERC721
    //-----------------
    //Custom

    struct Child {
        string collectionId;
        string equippedId;
        string ID;
        string metadata;
        string metadata_rarity;
    }

    struct Order {
        string UID;
        string Address;
    }

    //Events:
    //Emitted when order for 'UID' is created from 'Client' on RMRK.
    event createdRMRKOrder(address Client, string UID);

    //Emitted when order for 'UID' is created from 'Client' on MOVR.
    event createdMOVROrder(string Client, string UID);

    //Emitted when order for 'UID' is filled 'Client' on MOVR.
    event filledRMRKOrder(address Client, string UID);

    //Emitted when order for 'UID' is filled 'Client' on RMRK.
    event filledMOVROrder(string Client, string UID);

    //Variables:
    //Mapping from UID to ID.
    mapping(string => uint256) private _matchingU;

    //Mapping from ID to UID.
    mapping(uint256 => string) private _matchingI;

    //Mapping from address Client to mapping from UID to bool.
    //This storage opened orders on MOVR.
    mapping(address => mapping(string => bool)) private _ordersRMRK;

    //Mapping from Address on Kusama chain to bool.
    //This storage opened orders on RMRK.
    mapping(string => bool) private _storageRMRK;

    //Mapping drom address Client to uint.
    //This is a repository of overpaid money for a refund.
    mapping(address => uint256) private _lostMoney;

    //Mapping from UID to mapping from Number Child to Child.
    mapping(string => mapping(uint256 => Child)) private _storageMeta;

    //Mapping from address to mapping from UID to URI.
    //Storage completed orders, but not expected ones.
    mapping(address => mapping(string => string)) private _pendingOrderRMKR;

    //Stores nft transfer orders requiring processing (from MOVR to RMRK).
    Order[] private _ordersMOVR;

    //The amount of the commission for the payment of the server side.
    uint256 private _serverPayment = 0;

    //The amount of the commission for payment of the transaction.
    uint256 private _deployPayment = 0;

    //The address that creates the nft.
    address private _reciever =
        payable(0x43A2cCed6d1B7ba37173336AA794bAAB2cB1f830);

    //Address for receiving payments.
    address private _bank =
        payable(0xEc92783237998d58d3323880A5515A2a444Ed3E6);

    //Flags
    //Enables and disables NFT transfer payment.
    bool private _paymentsOn = false;

    //lock variable for reentrancy checks.
    bool private lock = false;

    //Functions:

    //Returns overpayments for the calling address.
    function myLostMoney() public view returns (uint256) {
        return _lostMoney[msg.sender];
    }

    //Allows you to collect overpayments of the calling address.
    function takeMoney() public nonReentrant() {
        require(_lostMoney[msg.sender] > 0, "You didn't lose any money!");
        uint _amount = _lostMoney[msg.sender];
        _lostMoney[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    //Commission payment function.
    function _pay() private nonReentrant() returns (bool result) {
        bool success;

        if (msg.value > _deployPayment + _serverPayment) {
            _lostMoney[msg.sender] =
                msg.value -
                (_deployPayment + _serverPayment);
        }

        (success, ) = _bank.call{value: _serverPayment}("");
        require(success, "Transfer failed.");

        (success, ) = _reciever.call{value: _deployPayment}("");
        require(success, "Transfer failed.");
    }

    /*
	Creates an order for the transfer of NFT from RMRK to MOVR.

	Requirements:
	Client - The recipient's address in the MOVR network;
	UID - NFT ID RMRK;
	*/
    function createRMRKOrder(address Client, string memory UID) public payable {
        if (_paymentsOn) {
            require(msg.value >= _serverPayment + _deployPayment);
            _pay();
        }
        require(bytes(UID).length != 0);
        require(Client != address(0));

        //Check pending Order
        if (bytes(_pendingOrderRMKR[Client][UID]).length > 0) {
            uint256 ID = _tokenIdCounter.current();
            _safeMint(Client, ID);
            _tokenIdCounter.increment();

            _matchingU[UID] = ID;
            _matchingI[ID] = UID;
            _setTokenURI(ID, _pendingOrderRMKR[Client][UID]);
            _pendingOrderRMKR[Client][UID] = "";
        } else {
            _ordersRMRK[Client][UID] = true;
        }

        emit createdRMRKOrder(Client, UID);
    }

    /*
	Creates an order for the transfer of NFT from MOVR to RMRK.

	Requirements:
	Client - The recipient's address in the Kusama chain;
	UID - NFT ID RMRK;
	*/
    function createMOVROrder(string memory Client, string memory UID)
        public
        payable
    {
        if (_paymentsOn) {
            require(msg.value >= _serverPayment + _deployPayment);
            _pay();
        }
        require(bytes(UID).length != 0);
        require(bytes(Client).length != 0);
        require(msg.sender == ownerOf(_matchingU[UID]));
        require(_storageRMRK[UID]);

        _burn(_matchingU[UID]);

        Order memory order;
        order.UID = UID;
        order.Address = Client;
        _ordersMOVR.push(order);
        emit createdMOVROrder(Client, UID);
    }

    /*
	Closes the order (RMRK => MOVR)
	If the NFT is expected on the MOVR side, then a duplicate of the NFT is created on the MOVR side and transferred to the waiting client
	Otherwise, a duplicate is created on the MOVR side and is recorded in marked as a pending order

	Requirements:
	Client - The recipient's address in the Kusama chain;
	UID - NFT ID RMRK;
	URI - Link to metadata;
	data - Array of nested nfts
	*/
    function fillRMRKOrder(
        address Client,
        string memory UID,
        string memory URI,
        Child[] memory data
    ) public onlyOwner {
        require(bytes(URI).length != 0);
        require(Client != address(0), "Dont fill 0 address!");

        if (_ordersRMRK[Client][UID]) {
            uint256 ID = _tokenIdCounter.current();
            _safeMint(Client, ID);
            _tokenIdCounter.increment();

            _matchingU[UID] = ID;
            _matchingI[ID] = UID;
            _setTokenURI(ID, URI);
            _storageRMRK[UID] = true;
            _ordersRMRK[Client][UID] = false;
            for (uint256 i = 0; i < data.length; i = i + 1) {
                _storageMeta[UID][i] = data[i];
            }

            emit filledRMRKOrder(Client, UID);
        } else {
            _storageRMRK[UID] = true;
            _pendingOrderRMKR[Client][UID] = URI;
            for (uint256 i = 0; i < data.length; i = i + 1) {
                _storageMeta[UID][i] = data[i];
            }

            emit filledRMRKOrder(Client, UID);
        }
    }

    /*
	Closes the orders (MOVR => RMRK)

	! Call only after orders are executed by the server side !

	Requirements:
	Count - Count number of executed orders;
	*/
    function fillMOVROrders(uint256 Count) public payable onlyOwner {
        for (uint256 i = 0; i < Count; i = i + 1) {
            _ordersMOVR.pop();
        }
    }

    //Get Functions
    //The functions return contract variables to display the contract status
    function getUID(uint256 ID) public view returns (string memory) {
        return _matchingI[ID];
    }

    function getCurrentSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function getMOVROrders() public view returns (Order[] memory) {
        return _ordersMOVR;
    }

    function getMeta(uint256 ID, uint256 i) public view returns (Child memory) {
        return _storageMeta[_matchingI[ID]][i];
    }

    function getID(string memory UID) public view returns (uint256) {
        return _matchingU[UID];
    }

    function getServerPayments() public view returns (uint256) {
        return _serverPayment;
    }

    function getDeployPayments() public view returns (uint256) {
        return _deployPayment;
    }

    function getAddressReceiver() public view returns (address) {
        return _reciever;
    }

    function getAddressBank() public view returns (address) {
        return _bank;
    }

    function paymentsOn() public view returns (bool) {
        return _paymentsOn;
    }

    //Set Functions
    //Function for setting up commissions
    function changeServerPayments(uint256 New) public onlyOwner {
        _serverPayment = New;
    }

    function changeDeployPayments(uint256 New) public onlyOwner {
        _deployPayment = New;
    }

    function changeAddressReciever(address New) public onlyOwner {
        _reciever = payable(New);
    }

    function changeAddressBank(address New) public onlyOwner {
        _bank = payable(New);
    }

    function switchFee(bool New) public onlyOwner {
        _paymentsOn = New;
    }
}
