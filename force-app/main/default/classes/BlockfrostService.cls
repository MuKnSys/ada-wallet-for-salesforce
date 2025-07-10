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

            if (endpoint.getStatusCode() == 404) {                
                return false;
            }

            Map<String, Object> totalData = (Map<String, Object>) JSON.deserializeUntyped(endpoint.getResponse().getBody());

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
    public static Map<String, Object> getAssetInfo(String assetId) {
        try {
            if (String.isBlank(assetId)) {
                return new Map<String, Object>{
                    'status' => 400,
                    'error' => 'Invalid asset ID provided'
                };
            }
            
            String projectId = AdaWalletsService.getBlockfrostProjectId();
            String url = '/assets/' + assetId;
            
            BlockfrostEndpoint endpoint = new BlockfrostEndpoint()
                .get()
                .setEndpoint(url)
                .setHeaders(new Map<String,String>{
                    'Project_id'=>projectId,
                    'Content-Type'=>'application/json',
                    'Accept'=>'application/json'
                })
                .send();
            
            Integer status = endpoint.getStatusCode();
            String body = endpoint.getResponse().getBody();
            
            if (status == 200) {
                try {
                    Map<String, Object> assetData = (Map<String, Object>) JSON.deserializeUntyped(body);
                    return assetData;
                } catch (Exception parseError) {
                    return new Map<String, Object>{
                        'status' => 500,
                        'error' => 'Failed to parse asset data: ' + parseError.getMessage(),
                        'rawBody' => body
                    };
                }
            } else if (status == 404) {
                return new Map<String, Object>{
                    'status' => 404,
                    'error' => 'Asset not found',
                    'assetId' => assetId
                };
            } else {
                return new Map<String, Object>{
                    'status' => status,
                    'error' => 'Blockfrost API error',
                    'body' => body,
                    'assetId' => assetId
                };
            }
        } catch (Exception e) {
            return new Map<String, Object>{
                'status' => 500,
                'error' => 'Apex exception: ' + e.getMessage(),
                'stackTrace' => e.getStackTraceString()
            };
        }
    }

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
        
        Blob cborBlob = EncodingUtil.convertFromHex(cborHex);
        req.setBodyAsBlob(cborBlob);
        
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                String txHash = res.getBody().trim();
                return txHash;
            } else {
                String errorBody = res.getBody();
                String errorMessage = 'Blockfrost API Error';
                
                try {
                    if (String.isNotBlank(errorBody) && errorBody.startsWith('{')) {
                        Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(errorBody);
                        if (errorResponse.containsKey('error')) {
                            Object errorObj = errorResponse.get('error');
                            if (errorObj instanceof String) {
                                errorMessage = (String) errorObj;
                            } else if (errorObj instanceof Map<String, Object>) {
                                Map<String, Object> errorMap = (Map<String, Object>) errorObj;
                                if (errorMap.containsKey('message')) {
                                    errorMessage = String.valueOf(errorMap.get('message'));
                                }
                            }
                        }
                        
                        if (errorMessage.contains('BadInputsUTxO') || errorMessage.contains('UtxoFailure')) {
                            errorMessage = 'UTXO Error: The transaction is trying to spend UTXOs that are invalid, already spent, or do not exist. ' + errorMessage;
                        }
                    }
                } catch (Exception parseError) {
                    errorMessage = 'Blockfrost API Error (Status: ' + res.getStatusCode() + ')';
                }
                
                return JSON.serialize(new Map<String,Object>{
                    'status' => res.getStatusCode(),
                    'error' => errorMessage,
                    'raw_response' => errorBody,
                    'error_type' => errorBody.contains('BadInputsUTxO') ? 'UTXO_ERROR' : 'GENERAL_ERROR'
                });
            }
        } catch (Exception e) {
            return JSON.serialize(new Map<String,Object>{
                'status' => 'error',
                'error' => 'Network or processing error: ' + e.getMessage(),
                'exception_type' => e.getTypeName()
            });
        }
    }

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
            return '[]';
        }

        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error' => 'Blockfrost address transactions API error'
        });
    }

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
            return '{}';
        }

        return JSON.serialize(new Map<String,Object>{
            'status' => endpoint.getStatusCode(),
            'error' => 'Blockfrost transaction details API error'
        });
    }

    @AuraEnabled(cacheable=false)
    public static String analyzeTransactionDirection(String txHash, List<String> walletAddresses) {
        try {
            if (String.isBlank(txHash)) {
                throw new BlockfrostEndpoint.BlockfrostAPIException('Transaction hash is required');
            }
            
            if (walletAddresses == null || walletAddresses.isEmpty()) {
                throw new BlockfrostEndpoint.BlockfrostAPIException('Wallet addresses are required');
            }
            
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
    
    private static Map<String, Object> analyzeTransactionDirectionFromData(Map<String, Object> txData, Set<String> walletAddresses) {
        Map<String, Object> analysis = new Map<String, Object>();
        
        try {
            Set<String> walletAddressesLower = new Set<String>();
            for (String addr : walletAddresses) {
                if (addr != null) walletAddressesLower.add(addr.toLowerCase());
            }

            List<Object> inputs = (List<Object>) txData.get('inputs');
            List<Object> outputs = (List<Object>) txData.get('outputs');
            
            if (inputs == null || outputs == null) {
                analysis.put('success', false);
                analysis.put('error', 'Transaction data missing inputs or outputs');
                return analysis;
            }
            
            Set<String> inputAddresses = new Set<String>();
            for (Object inputObj : inputs) {
                Map<String, Object> input = (Map<String, Object>) inputObj;
                String address = String.valueOf(input.get('address'));
                if (address != null && address != 'null') {
                    inputAddresses.add(address.toLowerCase());
                }
            }
            
            Set<String> outputAddresses = new Set<String>();
            for (Object outputObj : outputs) {
                Map<String, Object> output = (Map<String, Object>) outputObj;
                String address = String.valueOf(output.get('address'));
                if (address != null && address != 'null') {
                    outputAddresses.add(address.toLowerCase());
                }
            }
            
            Boolean hasWalletInputs = false;
            Boolean hasWalletOutputs = false;
            
            for (String inputAddr : inputAddresses) {
                if (walletAddressesLower.contains(inputAddr)) {
                    hasWalletInputs = true;
                    break;
                }
            }
            
            for (String outputAddr : outputAddresses) {
                if (walletAddressesLower.contains(outputAddr)) {
                    hasWalletOutputs = true;
                    break;
                }
            }
            
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
    
    private static List<String> getWalletAddressesInSet(Set<String> addressSet, Set<String> walletAddresses) {
        List<String> walletAddressesInSet = new List<String>();
        for (String addr : addressSet) {
            if (walletAddresses.contains(addr)) {
                walletAddressesInSet.add(addr);
            }
        }
        return walletAddressesInSet;
    }

    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }
}