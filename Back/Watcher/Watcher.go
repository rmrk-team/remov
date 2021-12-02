package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io/ioutil"
	"log"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

//JSON Request format
type Webhook struct {
	Id                       string        `json:"id"`
	Forsale                  int           `json:"forsale"`
	EquippedId               interface{}   `json:"equipped_id"`
	CreatedAt                time.Time     `json:"created_at"`
	CollectionId             string        `json:"collectionId"`
	Metadata                 string        `json:"metadata"`
	MetadataDescription      string        `json:"metadata_description"`
	MetadataImage            string        `json:"metadata_image"`
	MetadataName             string        `json:"metadata_name"`
	MetadataRarity           string        `json:"metadata_rarity"`
	MetadataRarityPercentage float64       `json:"metadata_rarity_percentage"`
	Owner                    string        `json:"owner"`
	Pending                  bool          `json:"pending"`
	Rootowner                string        `json:"rootowner"`
	Sn                       string        `json:"sn"`
	Symbol                   string        `json:"symbol"`
	UpdatedAt                time.Time     `json:"updated_at"`
	Burned                   string        `json:"burned"`
	Block                    int           `json:"block"`
	Children                 []interface{} `json:"children"`
	PrevOwner                string        `json:"prev_owner"`
	Timestamp                string        `json:"timestamp"`
	BridgeRemarks            []struct {
		Block           int    `json:"block"`
		Caller          string `json:"caller"`
		InteractionType string `json:"interaction_type"`
		Version         string `json:"version"`
		Remark          string `json:"remark"`
	} `json:"bridgeRemarks"`
}

//structure for loading settings
type Settings struct {
	AddrBridge_RMRK string `json:"AddrBridge_RMRK"`
	AddrHub         string `json:"AddrHub"`
	HMAC_mysecret   string `json:"HMAC_mysecret"`
	Delay           int    `json:"Delay"`
	Port            string `json:"Port"`
	PrivateKey      string `json:"PrivateKey"`
	RPC             string `json:"RPC"`
}

var Setting Settings

//Request Handler
func processingData(Data Webhook, buff bytes.Buffer) {

	//Connect with EVM
	client, err := ethclient.Dial(Setting.RPC)
	if err != nil {
		log.Fatal("Error connecting: ", err)
	}

	//Convert the key to the desired format
	privateKey, err := crypto.HexToECDSA(Setting.PrivateKey)
	if err != nil {
		log.Fatal(err)
	}

	//Generate pub key
	publicKey := privateKey.Public()

	//Convert pub key to the desired format
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
	if !ok {
		log.Fatal("cannot assert type: publicKey is not of type *ecdsa.PublicKey")
	}

	fromAddress := crypto.PubkeyToAddress(*publicKeyECDSA)

	//Get nonce
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		log.Fatal(err)
	}

	//Get gas price
	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Fatal(err)
	}

	//Creating an account
	auth := bind.NewKeyedTransactor(privateKey)
	auth.Nonce = big.NewInt(int64(nonce))
	auth.Value = big.NewInt(0)     // in wei
	auth.GasLimit = uint64(600000) // in units
	auth.GasPrice = gasPrice

	//Creating a contract image
	address := common.HexToAddress(Setting.AddrHub)
	main_hub, err := NewHub(address, client)
	if err != nil {
		log.Fatal(err)
	}

	//Get MOVR address from request
	temp := strings.Split(Data.BridgeRemarks[0].Remark, "RMRK::BRIDGE::2.0.0::MOVR::")[1]
	log.Println(temp)

	//Fill order on movr contract (hub) (RMRK =>MOVR)
	tx, err := main_hub.FillRMRKOrder(auth, common.HexToAddress(temp), Data.Id, Data.Metadata, Data.CollectionId)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("tx sent: ", tx.Hash().Hex())
}


//This function checks the validity of the request
func checkReliability(w http.ResponseWriter, r *http.Request) (bytes.Buffer, bool) {

	//Get body
	buff := new(bytes.Buffer)
	buff.ReadFrom(r.Body)

	//Check Null Body
	if r.Body == nil {
		http.Error(w, "", 400)
		log.Println("Error: Null Body!!!")
		return *buff, false
	}

	//Check HMAC
	if r.Header.Get("x-rmrk-signature") == "" {
		http.Error(w, "", 400)
		log.Println("Error: Null x-rmrk-signature!!!")
		return *buff, false
	} else {
		var rmrk_signature = r.Header.Get("x-rmrk-signature")
		h := hmac.New(sha256.New, []byte(Setting.HMAC_mysecret))
		h.Write([]byte(buff.String()))
		sha := "sha256=" + hex.EncodeToString(h.Sum(nil))
		if rmrk_signature != sha {
			http.Error(w, "", 500)
			log.Println("Error: Wrong HMAC!!!")
			return *buff, false
		}
		return *buff, true
	}
}

func main() {
	//Upload settings
	content, err := ioutil.ReadFile("Settings.json")
	if err != nil {
		log.Fatal("Error when opening file: ", err)
	}

	err = json.Unmarshal(content, &Setting)
	if err != nil {
		log.Fatal("Error during Unmarshal(): ", err)
	}
	log.Println(">Settings loaded")

	//Start server
	http.HandleFunc("/webhook", func(w http.ResponseWriter, r *http.Request) {
		log.Println(">New request!")

		buff, result := checkReliability(w, r)
		if !result {
			return
		}

		//Parsing json request
		var webhookData Webhook
		err := json.Unmarshal(buff.Bytes(), &webhookData)
		if err != nil {
			log.Println(err)
			return
		}

		//Check timestamp
		sendTime, err := strconv.Atoi(webhookData.Timestamp)
		if err != nil {
			log.Println(err)
		}
		if (sendTime + Setting.Delay) < int(time.Now().Unix()) {
			log.Println("Error: Late Request!!!")
			return
		}

		//Right Request
		if (webhookData.Rootowner == Setting.AddrBridge_RMRK) && (webhookData.BridgeRemarks != nil) {
			log.Println("<===> New Transfer:")
			log.Println("id:", webhookData.Id)
			log.Println("prev_owner:", webhookData.PrevOwner)
			log.Println("timestamp:", webhookData.Timestamp)
			log.Println("metadata", webhookData.Metadata)
			log.Println("children", webhookData.Children)
			log.Println(">Filling Order on MOVR")

			//Start goroutine for input
			//Filling RMRK order (RMRK => MOVR)
			go processingData(webhookData, buff)
		}
	})

	log.Println(">Server started")
	log.Fatal(http.ListenAndServe(":"+Setting.Port, nil))
}
