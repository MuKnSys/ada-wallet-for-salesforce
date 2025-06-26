public with sharing class BlockfrostService {
    private static final String BLOCKS_URL = '/blocks/latest';
    private static final String ADDRESS_TOTAL_URL = '/addresses/{address}/total';
    private static final String ADDRESS_EXTENDED_URL = '/addresses/{address}/extended';
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
     * Calls Blockfrost /addresses/{address}/extended endpoint and returns the raw JSON string.
     */
    @AuraEnabled(cacheable=false)
    public static String getAddressExtended(String address) {
        if (String.isBlank(address)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid address provided');
        }

        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = ADDRESS_EXTENDED_URL.replace('{address}', address);

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
            // Address not found on-chain. Return empty JSON so caller can handle.
            return '{}';
        }

        // Return an informative JSON payload instead of raising an exception so callers can log the error without surfacing it to users.
        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error'  => 'Blockfrost address extended API error'
        });
    }

    /**
     * Calls Blockfrost /addresses/{address}/total endpoint and returns raw JSON string.
     */
    @AuraEnabled(cacheable=false)
    public static String getAddressTotal(String address) {
        if (String.isBlank(address)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid address provided');
        }

        String projectId = AdaWalletsService.getBlockfrostProjectId();
        String url = ADDRESS_TOTAL_URL.replace('{address}', address);

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
            return '{}';
        }

        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error' => 'Blockfrost address total API error'
        });
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

    public static Boolean hasUtxos(String address) {
        String body = getAddressUtxos(address);
        List<Object> listResp = (List<Object>) JSON.deserializeUntyped(body);
        return !listResp.isEmpty();
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
     * Calls Blockfrost /addresses/{address}/utxos endpoint and returns detailed UTXO information
     * including transaction hash and output index for transaction building.
     */
    @AuraEnabled(cacheable=false)
    public static String getAddressUtxosDetailed(String address) {
        if (String.isBlank(address)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException('Invalid address provided');
        }
        
        String projectId = AdaWalletsService.getBlockfrostProjectId();
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
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == 404) {
            return '[]';
        }
        
        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error' => 'Blockfrost address UTXOs API error'
        });
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

    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }
}