public with sharing class BlockfrostService {
    private static final String BLOCKS_URL = '/blocks/latest';
    private static final String ADDRESS_TOTAL_URL = '/addresses/{address}/total';
    private static final String ADDRESS_UTXOS_URL = '/addresses/{address}/utxos';
    private static final String ASSET_METADATA_URL = '/assets/{asset}';
    private static final String EPOCHS_PARAMETERS_URL = '/epochs/latest/parameters';
    private static final String ADDRESS_TRANSACTIONS_URL = '/addresses/{address}/transactions';
    private static final String TYPE_RECEIVING = '0';
    private static final String TYPE_CHANGE = '1';
    
    public static String getBlockfrostConfig() {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(BLOCKS_URL)
            .setHeaders(
                new Map<String, String>{ 'Project_id' => projectId, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
            )
            .send();

        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else {
            throw new BlockfrostEndpoint.BlockfrostAPIException(
                System.Label.AdaWalletsSetup_BlockfrostGetConfigAPIError
            );
        }
    }
    
    public static Boolean isAddressUsed(String address) {
        try {            
            if (String.isBlank(address)) {                
                throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid address provided');
            }

            String projectId = AdaWalletsService.getBlockfrostProjectId();
            String url = ADDRESS_TOTAL_URL.replace('{address}', address);            
            BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
                .get()
                .setEndpoint(url)
                .setHeaders(
                    new Map<String, String>{ 'Project_id' => projectId, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
                )
                .send();

            // If 404, address doesn't exist on blockchain, so it's unused
            if (endpoint.getStatusCode() == 404) {                
                return false;
            }

            Map<String, Object> totalData = (Map<String, Object>) JSON.deserializeUntyped(endpoint.getResponse().getBody());

            // Extract tx_count which may deserialize as Decimal
            Object txObj = totalData.get('tx_count');
            Integer txCount = 0;
            if (txObj != null) {
                if (txObj instanceof Decimal) {
                    txCount = ((Decimal) txObj).intValue();
                } else if (txObj instanceof Integer) {
                    txCount = (Integer) txObj;
                } else if (txObj instanceof Long) {
                    txCount = ((Long) txObj).intValue();
                }
            }
            return txCount != null && txCount > 0;
        } catch (Exception e) {            
            throw new BlockfrostEndpoint.BlockfrostAPIException('Error checking address usage: ' + e.getMessage());
        }
    }
    
    public static Map<String, Object> getWalletTotalBalance(String walletId) {
        try {            
            // Query all UTXO_Address__c records for the wallet            
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getUTXOAddressesByWalletId(
                walletId, 
                new Set<String>{TYPE_RECEIVING, TYPE_CHANGE}
            );

            if (utxoAddresses.isEmpty()) {
                throw new AuraHandledException('No UTXO addresses found for Wallet ID: ' + walletId);
            }

            String projectId = AdaWalletsService.getBlockfrostProjectId();
            Map<String, Object> result = new Map<String, Object>();
            Map<String, Map<String, Object>> addressDetails = new Map<String, Map<String, Object>>();
            Map<String, Decimal> totalReceived = new Map<String, Decimal>();
            Map<String, Decimal> totalSent = new Map<String, Decimal>();

            // Fetch total data for each address
            for (UTXO_Address__c addr : utxoAddresses) {                
                String url = ADDRESS_TOTAL_URL.replace('{address}', addr.Address__c);
                BlockfrostEndpoint endpoint;
                try {
                    endpoint = new BlockfrostEndpoint()
                        .get()
                        .setEndpoint(url)
                        .setHeaders(
                            new Map<String, String>{ 'Project_id' => projectId, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
                        )
                        .send();
                } catch (Exception e) {                    
                    continue; // Skip this address and continue with others
                }

                try {
                    Map<String, Object> totalData = (Map<String, Object>) JSON.deserializeUntyped(endpoint.getResponse().getBody());                    

                    // Validate response structure
                    if (!totalData.containsKey('tx_count') || !totalData.containsKey('received_sum') || !totalData.containsKey('sent_sum')) {                        
                        continue;
                    }

                    Integer txCount = (Integer) totalData.get('tx_count');
                    List<Object> receivedSum = (List<Object>) totalData.get('received_sum');
                    List<Object> sentSum = (List<Object>) totalData.get('sent_sum');

                    // Store details for this address
                    addressDetails.put(addr.Address__c, new Map<String, Object>{
                        'type' => addr.Type__c,
                        'tx_count' => txCount,
                        'received_sum' => receivedSum,
                        'sent_sum' => sentSum
                    });

                    // Aggregate received amounts
                    for (Object assetObj : receivedSum) {
                        Map<String, Object> asset = (Map<String, Object>) assetObj;
                        String unit = (String) asset.get('unit');
                        String quantityStr = (String) asset.get('quantity');
                        if (String.isBlank(unit) || String.isBlank(quantityStr)) {                            
                            continue;
                        }
                        Decimal quantity = Decimal.valueOf(quantityStr);
                        totalReceived.put(unit, (totalReceived.get(unit) != null ? totalReceived.get(unit) : 0) + quantity);
                    }

                    // Aggregate sent amounts
                    for (Object assetObj : sentSum) {
                        Map<String, Object> asset = (Map<String, Object>) assetObj;
                        String unit = (String) asset.get('unit');
                        String quantityStr = (String) asset.get('quantity');
                        if (String.isBlank(unit) || String.isBlank(quantityStr)) {                            
                            continue;
                        }
                        Decimal quantity = Decimal.valueOf(quantityStr);
                        totalSent.put(unit, (totalSent.get(unit) != null ? totalSent.get(unit) : 0) + quantity);
                    }
                } catch (Exception e) {                    
                    continue;
                }
            }

            // Calculate total balance (received - sent) for each asset
            Map<String, Decimal> totalBalance = new Map<String, Decimal>();
            for (String unit : totalReceived.keySet()) {
                Decimal received = totalReceived.get(unit) != null ? totalReceived.get(unit) : 0;
                Decimal sent = totalSent.get(unit) != null ? totalSent.get(unit) : 0;
                totalBalance.put(unit, received - sent);
            }

            // Prepare the result map
            result.put('addressDetails', addressDetails);
            result.put('totalBalance', totalBalance);
            
            return result;
        } catch (Exception e) {            
            throw new BlockfrostEndpoint.BlockfrostAPIException('Error retrieving wallet balance: ' + e.getMessage());
        }
    }

    /**
     * Calls Blockfrost /addresses/{address}/utxos endpoint and returns raw JSON string (array).
     */
    @AuraEnabled(cacheable=false)
    public static String getAddressUtxos(String address) {
        if (String.isBlank(address)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid address');
        }
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = ADDRESS_UTXOS_URL.replace('{address}', address);
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(url)
            .setHeaders(new Map<String,String>{'Project_id'=>projectId,'Content-Type'=>'application/json','Accept'=>'application/json'})
            .send();
        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == 404) {
            return '[]';
        }
        throw new BlockfrostEndpoint.BlockfrostAPIException('UTXO call error status '+endpoint.getStatusCode());
    }

    @AuraEnabled(cacheable=false)
    public static String getAssetMetadata(String unit) {
        if (String.isBlank(unit)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid asset unit');
        }
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = ASSET_METADATA_URL.replace('{asset}', unit);
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(url)
            .setHeaders(new Map<String,String>{'Project_id'=>projectId,'Content-Type'=>'application/json','Accept'=>'application/json'})
            .send();
        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == 404) {
            return '{}';
        }
        throw new BlockfrostEndpoint.BlockfrostAPIException('Asset metadata error status '+endpoint.getStatusCode());
    }

    /**
     * Calls Blockfrost /epochs/latest/parameters endpoint and returns the raw JSON string.
     */
    @AuraEnabled(cacheable=false)
    public static String getEpochParameters() {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(EPOCHS_PARAMETERS_URL)
            .setHeaders(new Map<String, String>{
                'Project_id' => projectId,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json'
            })
            .send();

        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else {
            return JSON.serialize(new Map<String,Object>{
                'status' => endpoint.getStatusCode(),
                'error' => 'Blockfrost epochs parameters API error'
            });
        }
    }

    /**
     * Calls Blockfrost /blocks/latest endpoint and returns current slot with calculated TTL.
     * TTL = current_slot + 86400 (24-hour buffer).
     */
    @AuraEnabled(cacheable=false)
    public static String getCurrentSlotAndTTL() {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(BLOCKS_URL)
            .setHeaders(new Map<String, String>{
                'Project_id' => projectId,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json'
            })
            .send();

        if (endpoint.getStatusCode() == 200) {
            try {
                Map<String, Object> blockData = (Map<String, Object>) JSON.deserializeUntyped(endpoint.getResponse().getBody());
                
                // Extract slot number
                Object slotObj = blockData.get('slot');
                Long currentSlot = 0;
                if (slotObj != null) {
                    if (slotObj instanceof Long) {
                        currentSlot = (Long) slotObj;
                    } else if (slotObj instanceof Integer) {
                        currentSlot = (Long) ((Integer) slotObj);
                    } else if (slotObj instanceof Decimal) {
                        currentSlot = ((Decimal) slotObj).longValue();
                    }
                }
                
                // Calculate TTL with 24-hour buffer (86400 slots)
                Long ttl = currentSlot + 86400;
                
                // Return formatted response
                Map<String, Object> result = new Map<String, Object>{
                    'current_slot' => currentSlot,
                    'ttl' => ttl,
                    'buffer_slots' => 86400,
                    'buffer_hours' => 24
                };
                
                return JSON.serialize(result);
            } catch (Exception e) {
                return JSON.serialize(new Map<String,Object>{
                    'status' => 'error',
                    'error' => 'Failed to parse block data: ' + e.getMessage()
                });
            }
        } else {
            return JSON.serialize(new Map<String,Object>{
                'status' => endpoint.getStatusCode(),
                'error' => 'Blockfrost blocks latest API error'
            });
        }
    }    

    /**
     * Fetches UTXOs for multiple addresses and returns detailed information
     * including transaction hash and output index for each UTXO.
     */
    @AuraEnabled(cacheable=false)
    public static String getMultipleAddressUtxosDetailed(List<String> addresses) {
        if (addresses == null || addresses.isEmpty()) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('No addresses provided');
        }
        
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        Map<String, Object> result = new Map<String, Object>();
        
        for (String address : addresses) {
            try {
                String url = ADDRESS_UTXOS_URL.replace('{address}', address);
                BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
                    .get()
                    .setEndpoint(url)
                    .setHeaders(new Map<String, String>{
                        'Project_id' => projectId,
                        'Content-Type' => 'application/json',
                        'Accept' => 'application/json'
                    })
                    .send();
                    
                if (endpoint.getStatusCode() == 200) {
                    List<Object> utxos = (List<Object>) JSON.deserializeUntyped(endpoint.getResponse().getBody());
                    result.put(address, utxos);
                } else if (endpoint.getStatusCode() == 404) {
                    result.put(address, new List<Object>());
                } else {
                    result.put(address, new Map<String, Object>{
                        'status' => endpoint.getStatusCode(),
                        'error' => 'Blockfrost API error'
                    });
                }
            } catch (Exception e) {
                result.put(address, new Map<String, Object>{
                    'status' => 'error',
                    'error' => 'Failed to fetch UTXOs: ' + e.getMessage()
                });
            }
        }
        
        return JSON.serialize(result);
    }

    /**
     * Submits a signed transaction to Blockfrost /tx/submit endpoint.
     * @param cborHex The signed transaction in CBOR hex format
     * @return The transaction hash if successful, or error message
     */
    @AuraEnabled
    public static String submitTransaction(String cborHex) {
        if (String.isBlank(cborHex)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('CBOR hex is required');
        }
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = '/tx/submit';
        HttpRequest req = new HttpRequest();
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint().setEndpoint(url);
        req.setEndpoint(endpoint.request.getEndpoint());
        req.setMethod('POST');
        req.setHeader('project_id', projectId);
        req.setHeader('Content-Type', 'application/cbor');
        req.setHeader('Accept', 'application/json');
        // Convert hex string to binary
        Blob cborBlob = EncodingUtil.convertFromHex(cborHex);
        req.setBodyAsBlob(cborBlob);
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                // Blockfrost returns the transaction hash as plain text
                return res.getBody();
            } else {
                return JSON.serialize(new Map<String,Object>{
                    'status' => res.getStatusCode(),
                    'error' => res.getBody()
                });
            }
        } catch (Exception e) {
            return JSON.serialize(new Map<String,Object>{
                'status' => 'error',
                'error' => e.getMessage()
            });
        }
    }

    /**
     * Calls Blockfrost /addresses/{address}/transactions endpoint and returns the raw JSON array.
     * Returns list of transactions for the given address with tx_hash, tx_index, block_height, and block_time.
     */
    @AuraEnabled(cacheable=false)
    public static String getAddressTransactions(String address) {
        if (String.isBlank(address)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid address provided');
        }

        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = ADDRESS_TRANSACTIONS_URL.replace('{address}', address);

        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(url)
            .setHeaders(new Map<String, String>{
                'Project_id' => projectId,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json'
            })
            .send();

        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == 404) {
            // Address not found on-chain or has no transactions. Return empty array.
            return '[]';
        }

        // Return error information as JSON so callers can handle gracefully
        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error' => 'Blockfrost address transactions API error'
        });
    }

    /**
     * Determines if a transaction is inbound or outbound for a specific wallet
     * by analyzing the transaction's inputs and outputs using the /txs/{hash} endpoint.
     * 
     * @param txHash The transaction hash to analyze
     * @param walletAddresses Set of addresses belonging to the wallet
     * @return Map containing transaction direction analysis
     */
    @AuraEnabled(cacheable=false)
    public static String analyzeTransactionDirection(String txHash, List<String> walletAddresses) {
        try {
            if (String.isBlank(txHash)) {
                throw new BlockfrostEndpoint.BlockfrostAPIException('Transaction hash is required');
            }
            
            if (walletAddresses == null || walletAddresses.isEmpty()) {
                throw new BlockfrostEndpoint.BlockfrostAPIException('Wallet addresses are required');
            }
            
            // Convert wallet addresses to a set for efficient lookup
            Set<String> walletAddressSet = new Set<String>(walletAddresses);
            
            String projectId = AdaWalletsService.getBlockfrostProjectId();
            String url = '/txs/' + txHash;
            
            BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
                .get()
                .setEndpoint(url)
                .setHeaders(new Map<String, String>{
                    'Project_id' => projectId,
                    'Content-Type' => 'application/json',
                    'Accept' => 'application/json'
                })
                .send();
                
            if (endpoint.getStatusCode() == 200) {
                Map<String, Object> txData = (Map<String, Object>) JSON.deserializeUntyped(endpoint.getResponse().getBody());
                
                // Analyze transaction direction
                Map<String, Object> analysis = analyzeTransactionDirectionFromData(txData, walletAddressSet);
                
                return JSON.serialize(analysis);
            } else if (endpoint.getStatusCode() == 404) {
                return JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'error' => 'Transaction not found',
                    'status' => 404
                });
            } else {
                return JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'error' => 'Blockfrost API error',
                    'status' => endpoint.getStatusCode()
                });
            }
        } catch (Exception e) {
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => 'Error analyzing transaction direction: ' + e.getMessage()
            });
        }
    }
    
    /**
     * Analyzes transaction direction from transaction data
     * @param txData The transaction data from Blockfrost
     * @param walletAddresses Set of wallet addresses to check against
     * @return Map containing direction analysis
     */
    private static Map<String, Object> analyzeTransactionDirectionFromData(Map<String, Object> txData, Set<String> walletAddresses) {
        Map<String, Object> analysis = new Map<String, Object>();
        
        try {
            // Normalize wallet addresses to lower case for robust comparison
            Set<String> walletAddressesLower = new Set<String>();
            for (String addr : walletAddresses) {
                if (addr != null) walletAddressesLower.add(addr.toLowerCase());
            }

            // Get inputs and outputs
            List<Object> inputs = (List<Object>) txData.get('inputs');
            List<Object> outputs = (List<Object>) txData.get('outputs');
            
            if (inputs == null || outputs == null) {
                analysis.put('success', false);
                analysis.put('error', 'Transaction data missing inputs or outputs');
                return analysis;
            }
            
            // Analyze inputs (where funds come from)
            Set<String> inputAddresses = new Set<String>();
            for (Object inputObj : inputs) {
                Map<String, Object> input = (Map<String, Object>) inputObj;
                String address = String.valueOf(input.get('address'));
                if (address != null && address != 'null') {
                    inputAddresses.add(address.toLowerCase());
                }
            }
            
            // Analyze outputs (where funds go to)
            Set<String> outputAddresses = new Set<String>();
            for (Object outputObj : outputs) {
                Map<String, Object> output = (Map<String, Object>) outputObj;
                String address = String.valueOf(output.get('address'));
                if (address != null && address != 'null') {
                    outputAddresses.add(address.toLowerCase());
                }
            }
            
            // Determine transaction direction
            Boolean hasWalletInputs = false;
            Boolean hasWalletOutputs = false;
            
            // Check if any inputs belong to our wallet
            for (String inputAddr : inputAddresses) {
                if (walletAddressesLower.contains(inputAddr)) {
                    hasWalletInputs = true;
                    break;
                }
            }
            
            // Check if any outputs belong to our wallet
            for (String outputAddr : outputAddresses) {
                if (walletAddressesLower.contains(outputAddr)) {
                    hasWalletOutputs = true;
                    break;
                }
            }
            
            // Determine transaction type
            String transactionType;
            String direction;
            Boolean isInbound = false;
            Boolean isOutbound = false;
            Boolean isInternal = false;
            
            if (hasWalletInputs && hasWalletOutputs) {
                transactionType = 'Internal Transfer';
                direction = 'Internal';
                isInternal = true;
            } else if (hasWalletOutputs) {
                transactionType = 'Inbound';
                direction = 'Inbound';
                isInbound = true;
            } else if (hasWalletInputs) {
                transactionType = 'Outbound';
                direction = 'Outbound';
                isOutbound = true;
            } else {
                transactionType = 'External';
                direction = 'External';
            }
            
            // Build result
            analysis.put('success', true);
            analysis.put('transactionType', transactionType);
            analysis.put('direction', direction);
            analysis.put('isInbound', isInbound);
            analysis.put('isOutbound', isOutbound);
            analysis.put('isInternal', isInternal);
            analysis.put('inputAddresses', new List<String>(inputAddresses));
            analysis.put('outputAddresses', new List<String>(outputAddresses));
            analysis.put('walletInputAddresses', getWalletAddressesInSet(inputAddresses, walletAddressesLower));
            analysis.put('walletOutputAddresses', getWalletAddressesInSet(outputAddresses, walletAddressesLower));
            analysis.put('netAmount', txData.get('netAmount'));
            analysis.put('netAmountADA', txData.get('netAmountADA'));
            analysis.put('totalInputLovelace', txData.get('totalInputLovelace'));
            analysis.put('totalOutputLovelace', txData.get('totalOutputLovelace'));
            analysis.put('fee', txData.get('fees'));
            analysis.put('blockHeight', txData.get('block_height'));
            analysis.put('blockTime', txData.get('block_time'));
            analysis.put('slot', txData.get('slot'));
        } catch (Exception e) {
            analysis.put('success', false);
            analysis.put('error', 'Error analyzing transaction data: ' + e.getMessage());
        }
        
        return analysis;
    }
    
    /**
     * Helper method to get wallet addresses that are in a given set
     */
    private static List<String> getWalletAddressesInSet(Set<String> addressSet, Set<String> walletAddresses) {
        List<String> walletAddressesInSet = new List<String>();
        for (String addr : addressSet) {
            if (walletAddresses.contains(addr)) {
                walletAddressesInSet.add(addr);
            }
        }
        return walletAddressesInSet;
    }

    /**
     * Analyzes multiple transactions to determine their direction for a wallet
     * @param txHashes List of transaction hashes to analyze
     * @param walletAddresses List of addresses belonging to the wallet
     * @return Map containing analysis for each transaction
     */
    @AuraEnabled(cacheable=false)
    public static String analyzeMultipleTransactionDirections(List<String> txHashes, List<String> walletAddresses) {
        try {
            if (txHashes == null || txHashes.isEmpty()) {
                throw new BlockfrostEndpoint.BlockfrostAPIException('Transaction hashes are required');
            }
            
            if (walletAddresses == null || walletAddresses.isEmpty()) {
                throw new BlockfrostEndpoint.BlockfrostAPIException('Wallet addresses are required');
            }
            
            Map<String, Object> results = new Map<String, Object>();
            
            for (String txHash : txHashes) {
                try {
                    String analysis = analyzeTransactionDirection(txHash, walletAddresses);
                    Map<String, Object> analysisMap = (Map<String, Object>) JSON.deserializeUntyped(analysis);
                    results.put(txHash, analysisMap);
                } catch (Exception e) {
                    results.put(txHash, new Map<String, Object>{
                        'success' => false,
                        'error' => 'Failed to analyze transaction: ' + e.getMessage()
                    });
                }
            }
            
            return JSON.serialize(results);
        } catch (Exception e) {
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => 'Error analyzing multiple transactions: ' + e.getMessage()
            });
        }
    }

    /**
     * Gets detailed transaction information from Blockfrost
     * @param txHash The transaction hash to get details for
     * @return JSON string containing full transaction details
     */
    @AuraEnabled(cacheable=false)
    public static String getTransactionDetails(String txHash) {
        if (String.isBlank(txHash)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Transaction hash is required');
        }

        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = '/txs/' + txHash;

        BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
            .get()
            .setEndpoint(url)
            .setHeaders(new Map<String, String>{
                'Project_id' => projectId,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json'
            })
            .send();

        if (endpoint.getStatusCode() == 200) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == 404) {
            // Transaction not found. Return empty object.
            return '{}';
        }

        // Return error information as JSON so callers can handle gracefully
        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error' => 'Blockfrost transaction details API error'
        });
    }

    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }

    public static void publishWalletSyncEvent(Id walletId, String action) {
        WalletSyncEvent__e event = new WalletSyncEvent__e(
                WalletId__c = walletId,
                Action__c = action
            );
        EventBus.publish(event);
    }
}