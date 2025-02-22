-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_KEY := 

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; 

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url $(ALCHEMY_RPC_URL) --private-key $(METAMASK_PRIVATE_KEY) --broadcast

ifeq ($(findstring --network ethereum,$(ARGS)),--network ethereum)
	NETWORK_ARGS := --rpc-url $(ALCHEMY_RPC_URL) --private-key $(METAMASK_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy:
	@forge script script/DeployEscrowAndFactory.s.sol:DeployEscrowAndFactory $(NETWORK_ARGS)





verify:
	@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(address,address,address,address,uint256)" "$(STABLECOIN)" "$(FEECOLLECTOR)" "$(ESCROW)" "$(YAPORACLE)" "$(KOLID)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0xb46B77179ef9A486F2C6E3Acc3F605526dcdE17E src/YapOrderBook.sol:YapOrderBook
#@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(address,address)" "$(USDC)" "$(FACTORY)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0x0f9ee075C54130b316BCc1624BeD52FD3420be7B src/YapEscrow.sol:YapEscrow
#@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(address)" "$(ESCROW)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0xBaDdB642d039421d9307cc0Eb8FfA24569a695AB src/YapOrderBookFactory.sol:YapOrderBookFactory
#@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(address)" "$(UPDATER)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0x8ad244404B40882A3447ABF74A78227bCD15E74A src/YapOracle.sol:YapOracle
#@forge verify-contract --chain-id 84532 --watch --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0xE9f2fA46087D0B2A08a2fB6eE960f03841a17Eda 
#@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(string,string,uint256,address[3],uint256[3],address)" "$(NAME)" "$(SYMBOL)" "$(MAX_SUPPLY)" "[$(ALLOCATION_ADDY1),$(ALLOCATION_ADDY2),$(ALLOCATION_ADDY3)]" "[$(ALLOCATIONAMOUNT1),$(ALLOCATIONAMOUNT2),$(ALLOCATIONAMOUNT3)]" "$(FACTORY)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.24 0xe2A1A3c40dFE8e29e00f25f50C113FF9b06ac912 
	

