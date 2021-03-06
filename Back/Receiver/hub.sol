/*
-----------Compiler Bug Summary performed by pragmaBugCheck (Written by @Rhynorater)-----------
Current File Name: C:\Users\Nethny\Desktop\Bridge\bridge-contracts\pragmaBugCheck\HUB_v0.2.sol
Detected Semantic Version: ^0.8.0
Detected Possible Compiler Bugs:
* medium - KeccakCaching
* very low - SignedImmutables
* very low - ABIDecodeTwoDimensionalArrayMemory
* very low - UserDefinedValueTypesBug

-----------Thanks for using pragmaBugCheck!-----------
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

//@author Nethny [TIIK]
contract Hub is ERC721, Ownable{
    using Counters for Counters.Counter;
    constructor() ERC721("Dublicate_RMRK","DRMRK"){}

    Counters.Counter private _tokenIdCounter;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

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

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
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

    function Mint(address to) public onlyOwner returns (uint) {
        uint temp = _tokenIdCounter.current();
        _safeMint(to, temp);
        _tokenIdCounter.increment();
        return temp;
    }

    struct Order{
        string  UID;
        string Address;
    }

    //Events
    event createdRMRKOrder(address Client, string UID);
    event createdMOVROrder(string Client, string UID);
    event filledRMRKOrder(address Client, string UID);
    event filledMOVROrder(string Client, string UID);

    //Some variables
    mapping (string => uint) private _matching;
    mapping (address => mapping(string => bool)) private _ordersRMRK;
    mapping (string => bool)private _storageRMRK;
    mapping (address => uint)private _lostMoney;
    mapping (uint => string)private _storageMeta;

    //pending
    mapping (address => mapping(string => bool)) private _pendingOrderRMKR;

    Order[] private _ordersMOVR;

    uint private _serverPayment = 0;
    uint private _deployPayment = 0;
    address payable private _reciever = payable(0x43A2cCed6d1B7ba37173336AA794bAAB2cB1f830);
    address payable private _bank = payable(0xEc92783237998d58d3323880A5515A2a444Ed3E6);
    address Bridge = address(0);

    //Flags
    bool private _paymentsOn = false;

    //Functions

    function initialize(address MyAddress) onlyOwner public{
        Bridge = MyAddress;
    }

    function myLostMoney()public view returns(uint){
        return _lostMoney[msg.sender];
    }

    function takeMoney()public {
        require(_lostMoney[msg.sender]>0, "You didn't lose any money!");
        payable(msg.sender).transfer(_lostMoney[msg.sender]);
    }

    function _pay()private returns (bool result){
        _reciever.transfer(_deployPayment);
        _bank.transfer(_serverPayment);
        if(msg.value > _deployPayment + _serverPayment){
            _lostMoney[msg.sender] = msg.value - _deployPayment + _serverPayment;
        }
        return true;
    }

    function createRMRKOrder(address Client, string memory UID) public payable {
        require(Bridge != address(0), "Please initialize the contract!");
        if(_paymentsOn){
            require(msg.value >= _serverPayment + _deployPayment);
            _pay();
        }
        require(bytes(UID).length != 0);
        require(Client != address(0));

        //Check pending Order
        if(_pendingOrderRMKR[Client][UID]){
            safeTransferFrom(Bridge, Client, _matching[UID]);
        }else{
            _ordersRMRK[Client][UID] = true;
        }

        emit createdRMRKOrder(Client,UID);
    }

    function createMOVROrder(string memory Client, string memory UID)public payable{
        require(Bridge != address(0), "Please initialize the contract!");
        if(_paymentsOn){
            require(msg.value >= _serverPayment + _deployPayment);
            _pay();
        }
        require(bytes(UID).length != 0);
        require(bytes(Client).length != 0);
        require(msg.sender == ownerOf(_matching[UID]));
        require(_storageRMRK[UID]);

        safeTransferFrom(msg.sender, Bridge, _matching[UID]);
        _burn(_matching[UID]);

        Order memory order;
        order.UID = UID;
        order.Address = Client;
        _ordersMOVR.push(order);
        emit createdMOVROrder(Client,UID);
    }

    function fillRMRKOrder(address Client, string memory UID, string memory URI, string memory data) onlyOwner public{
        require(Bridge != address(0), "Please initialize the contract!");
        require(bytes(URI).length != 0);
        require(bytes(data).length != 0);
        require(Client != address(0), "Dont fill 0 address!");

        if(_ordersRMRK[Client][UID]){
            uint ID = Mint(Client);

            _matching[UID] = ID;
            _setTokenURI(ID,URI);
            _storageRMRK[UID] = true;
            _ordersRMRK[Client][UID] = false;
            _storageMeta[ID] = data;

            emit filledRMRKOrder(Client,UID);
        }else{
            uint ID = Mint(Bridge);

            _matching[UID] = ID;
            _setTokenURI(ID,URI);
            _storageRMRK[UID] = true;
            _pendingOrderRMKR[Client][UID]=true;
            _storageMeta[ID] = data;

            emit filledRMRKOrder(Bridge,UID);
        }
    }

    function fillMOVROrders() onlyOwner public{
        for (uint i =0;i <= _ordersMOVR.length; i = i + 1){
            _storageRMRK[_ordersMOVR[i].UID] = false;
        }

        while(_ordersMOVR.length != 0){
            _ordersMOVR.pop();
        }
    }

    //Get Functions
    function getMeta(uint ID)public view returns (string memory){
        return _storageMeta[ID];
    }

    function getID(string memory UID)public view returns (uint){
        return _matching[UID];
    }


    function getServerPayments() public view returns (uint){
        return _serverPayment;
    }

    function getDeployPayments() public view returns (uint){
        return _deployPayment;
    }

    function getAddressReciever() public view returns (address){
        return _reciever;
    }

    function getAddressBank() public view returns (address){
        return _bank;
    }

    //Set Functions
    function addMOVROrders(string memory Client, string memory UID) onlyOwner public{
        Order memory order;
        order.UID = UID;
        order.Address = Client;
        _ordersMOVR.push(order);
    }

    function changeServerPayments(uint New) onlyOwner public{
        _serverPayment = New;
    }

    function changeDeployPayments(uint New) onlyOwner public{
        _deployPayment = New;
    }

    function changeAddressReciever(address New) onlyOwner public{
        _reciever = payable(New);
    }

    function changeAddressBank(address New) onlyOwner public{
        _bank = payable(New);
    }

    function switchFee(bool New)onlyOwner public{
        _paymentsOn = New;
    }
}
