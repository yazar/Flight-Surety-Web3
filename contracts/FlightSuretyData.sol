pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false


    struct AirlineInfo {
        address walletAddress;
        string name;
        uint256 fundAmount;
        bool authorized;
    }

    mapping(address => AirlineInfo) private airlines;
    mapping(address => uint256) private airlineFunds;

    mapping(address => uint256) private voteCounts;

    struct Passenger {
        address passengerWallet;
        mapping(string => uint256) insuranceAmounts;
        uint256 credit;
    }

    mapping(address => Passenger) private passengers;

    address[] public passengerAddresses;

    uint8 private constant MULTIPARTY_COUNT = 4;
    uint256  airlineCount = 0;

    uint256 public constant FUND_AMOUNT = 10 ether;
    uint256 public constant MAX_INSURANCE_AMOUNT = 1 ether;

    mapping(address => bool) private candidatedAirlines;


    struct FlightData {
        address airline;
        bytes32 flightNumber;
        uint256 timestamp; 
        string flightName;       
        uint8 statusCode;
        bool registered;
    }

    mapping(bytes32 => FlightData) flightDatas;


    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                ) 
                                public 
    {
        contractOwner = msg.sender;
        passengerAddresses = new address[](0);


        airlines[msg.sender] = AirlineInfo({
            walletAddress : msg.sender,
            name : "Yazar Airlines",
            fundAmount : 0,
            authorized : true
        });
        airlineCount = 1;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus
                            (
                                bool mode
                            ) 
                            external
                            requireContractOwner 
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline
                            (  
                                address airlineAddress,
                                string airlineName
                            )
                            external
                            requireIsOperational
                            returns(bool, uint256)
    {
        require(airlines[msg.sender].authorized, "not authorized");
        require(candidatedAirlines[airlineAddress] == false, "already registered, make fund to be authorized");

        if(airlineCount < MULTIPARTY_COUNT)
        {
            airlines[airlineAddress] = AirlineInfo ( {
                walletAddress : airlineAddress,
                name : airlineName,
                fundAmount : 0,
                authorized : false
            });
            candidatedAirlines[airlineAddress] = true;
        }
        else
        {
            voteCounts[airlineAddress]++;

            if(voteCounts[airlineAddress] >= airlineCount.div(2))
            {
                airlines[airlineAddress] = AirlineInfo ( {
                    walletAddress : airlineAddress,
                    name : airlineName,
                    fundAmount : 0,
                    authorized : false
                });
                candidatedAirlines[airlineAddress] = true;
            }
        }

        return (true, voteCounts[airlineAddress]);
    }


   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy
                            (              
                                bytes32 flightCode               
                            )
                            external
                            payable
                            requireIsOperational
    {
        require(flightDatas[flightCode].registered, "could not found flight, check your flight code");
        require(msg.sender == tx.origin, "Contracts cannot use this function");
        require(msg.value > 0, "You need to send some ether to pay for insurance");

        string memory flightName = flightDatas[flightCode].flightName;

        if(passengers[msg.sender].passengerWallet == address(0)) // add new passenger
        {
            passengers[msg.sender] = Passenger({
                passengerWallet : msg.sender,
                credit : 0
            });

            passengers[msg.sender].insuranceAmounts[flightName] = 0;

            passengerAddresses.push(msg.sender);
        }

        if(passengers[msg.sender].insuranceAmounts[flightName].add(msg.value) > MAX_INSURANCE_AMOUNT)
            {
                uint256 extraMoney = (passengers[msg.sender].insuranceAmounts[flightName].add(msg.value)).sub(MAX_INSURANCE_AMOUNT);

                passengers[msg.sender].insuranceAmounts[flightName] = MAX_INSURANCE_AMOUNT;

                msg.sender.transfer(extraMoney);
            }
        else {
                passengers[msg.sender].insuranceAmounts[flightName] = passengers[msg.sender].insuranceAmounts[flightName].add(msg.value);
            }
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                    bytes32 flightCode 
                                )
                                internal
                                requireIsOperational
    {
        string memory flightName = flightDatas[flightCode].flightName;

        for (uint256 i = 0; i < passengerAddresses.length; i++) {
            if(passengers[passengerAddresses[i]].insuranceAmounts[flightName] > 0) 
            { 
                uint256 insurancePrice = passengers[passengerAddresses[i]].insuranceAmounts[flightName];
                passengers[passengerAddresses[i]].insuranceAmounts[flightName] = 0;
                passengers[passengerAddresses[i]].credit += insurancePrice + insurancePrice.div(2);
            }
        }
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                                address passengerAddress
                            )
                            external
                            payable
                            requireIsOperational
    {
        require(msg.sender == tx.origin, "Contracts cannot use this function");
        require(passengers[passengerAddress].passengerWallet != address(0), "Passenger is not recorded");
        require(passengers[passengerAddress].credit > 0, "Credit amount is 0");

        uint256 credit = passengers[passengerAddress].credit;
        require(address(this).balance > credit, "We dont have enough funds, system bankrupt");

        passengers[passengerAddress].credit = 0;
        passengerAddress.transfer(credit);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund
                            (   
                            )
                            public
                            payable
    {
        require(candidatedAirlines[msg.sender], "not voted enough");

        airlines[msg.sender].fundAmount += msg.value;

        require(airlines[msg.sender].fundAmount >= FUND_AMOUNT, "not funded enough, plase send 10 ether minimum in total");

        airlines[msg.sender].authorized = true;

    }

    function registerFlight (
                            string flight,
                            uint256 timestamp
                            ) 
                            requireIsOperational
                            external
    {
        require(airlines[msg.sender].authorized, "airline not authorized");

        bytes32 flightCode = getFlightKey(msg.sender, flight);

        require(flightDatas[flightCode].registered == false, "flight already registered");

        flightDatas[flightCode] = FlightData( {
            airline : msg.sender,
            flightNumber : flightCode,
            flightName: flight,       
            timestamp : timestamp,
            statusCode : 0,
            registered : true
        });

    }

    function updateFlightData(
                            string flight,
                            uint256 timestamp,
                            address airline,
                            uint8 statusCode
                            ) 
                            requireIsOperational
                            external
    {
        bytes32 flightCode = getFlightKey(msg.sender, flight);
        require(flightDatas[flightCode].registered, "could not found flight");

        flightDatas[flightCode] = FlightData( {
            airline : airline,
            flightNumber : flightCode,
            flightName: flight,       
            timestamp : timestamp,
            statusCode : statusCode,
            registered : true
        });

        if(statusCode == 20)
            creditInsurees(flightCode);

    } 



    function getFlightKey
                        (
                            address airline,
                            string memory flight
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() 
                            external 
                            payable 
    {
        fund();
    }


}

