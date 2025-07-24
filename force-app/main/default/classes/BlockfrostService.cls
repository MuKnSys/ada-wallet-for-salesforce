/**
 * Service class for interacting with the Blockfrost API
 * Provides methods for querying blockchain data, submitting transactions, and analyzing transaction directions
 */
public with sharing class BlockfrostService {
    // API Endpoints
    private static final String BLOCKS_URL = '/blocks/latest';
    private static final String ADDRESS_TOTAL_URL = '/addresses/{address}/total';
    private static final String ADDRESS_UTXOS_URL = '/addresses/{address}/utxos';
    private static final String ASSET_METADATA_URL = '/assets/{asset}';
    private static final String EPOCHS_PARAMETERS_URL = '/epochs/latest/parameters';
    private static final String ADDRESS_TRANSACTIONS_URL = '/addresses/{address}/transactions';
    private static final String TRANSACTION_DETAILS_URL = '/txs/{txHash}';
    private static final String TRANSACTION_SUBMIT_URL = '/tx/submit';
    
    // Transaction Types
    private static final String TYPE_RECEIVING = '0';
    private static final String TYPE_CHANGE = '1';
    
    // HTTP Status Codes
    private static final Integer STATUS_OK = 200;
    private static final Integer STATUS_NOT_FOUND = 404;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_SERVER_ERROR = 500;
    
    // Error Messages
    private static final String ERROR_INVALID_ADDRESS = 'Invalid address provided';
    private static final String ERROR_INVALID_ASSET_ID = 'Invalid asset ID provided';
    private static final String ERROR_TX_HASH_REQUIRED = 'Transaction hash is required';
    private static final String ERROR_CBOR_REQUIRED = 'CBOR hex is required';
    private static final String ERROR_WALLET_ADDRESSES_REQUIRED = 'Wallet addresses are required';
    private static final String ERROR_TX_HASHES_REQUIRED = 'Transaction hashes are required';
    private static final String ERROR_ADDRESS_REQUIRED = 'Address is required';
    
    // =============================================================================
    // PUBLIC API METHODS
    // =============================================================================
    
    /**
     * Get the latest Blockfrost configuration
     * @return String JSON response from Blockfrost API
     * @throws BlockfrostEndpoint.BlockfrostAPIException if API call fails
     */
    public static String getBlockfrostConfig() {
        BlockfrostEndpoint endpoint = createGetEndpoint(BLOCKS_URL);
        endpoint.send();

        if (endpoint.getStatusCode() == STATUS_OK) {
            return endpoint.getResponse().getBody();
        } else {
            throw new BlockfrostEndpoint.BlockfrostAPIException(
                System.Label.AdaWalletsSetup_BlockfrostGetConfigAPIError
            );
        }
    }
    
    /**
     * Check if an address has been used (has transaction history)
     * @param address The address to check
     * @return Boolean true if address has been used, false otherwise
     * @throws BlockfrostEndpoint.BlockfrostAPIException if API call fails
     */
    public static Boolean isAddressUsed(String address) {
        try {            
            validateAddress(address);

            String url = ADDRESS_TOTAL_URL.replace('{address}', address);            
            BlockfrostEndpoint endpoint = createGetEndpoint(url);
            endpoint.send();

            if (endpoint.getStatusCode() == STATUS_NOT_FOUND) {                
                return false;
            }

            Map<String, Object> totalData = parseJsonResponse(endpoint.getResponse().getBody());
            Integer txCount = extractTransactionCount(totalData);
            return txCount != null && txCount > 0;
        } catch (Exception e) {            
            throw new BlockfrostEndpoint.BlockfrostAPIException('Error checking address usage: ' + e.getMessage());
        }
    }
    
    /**
     * Get UTXOs for a specific address
     * @param address The address to query
     * @return String JSON array of UTXOs
     * @throws BlockfrostEndpoint.BlockfrostAPIException if API call fails
     */
    public static String getAddressUtxos(String address) {
        validateAddress(address);
        
        String url = ADDRESS_UTXOS_URL.replace('{address}', address);
        BlockfrostEndpoint endpoint = createGetEndpoint(url);
        endpoint.send();
        
        if (endpoint.getStatusCode() == STATUS_OK) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == STATUS_NOT_FOUND) {
            return '[]';
        }
        throw new BlockfrostEndpoint.BlockfrostAPIException('UTXO call error status ' + endpoint.getStatusCode());
    }
    
    /**
     * Get asset information by asset ID
     * @param assetId The asset ID to query
     * @return Map<String, Object> containing asset information or error details
     */
    public static Map<String, Object> getAssetInfo(String assetId) {
        try {
            if (String.isBlank(assetId)) {
                return createErrorResponse(STATUS_BAD_REQUEST, ERROR_INVALID_ASSET_ID);
            }
            
            String url = '/assets/' + assetId;
            BlockfrostEndpoint endpoint = createGetEndpoint(url);
            endpoint.send();
            
            return handleAssetInfoResponse(endpoint, assetId);
        } catch (Exception e) {
            return createErrorResponse(STATUS_SERVER_ERROR, 'Apex exception: ' + e.getMessage(), e.getStackTraceString());
        }
    }
    
    /**
     * Get current epoch parameters
     * @return String JSON response containing epoch parameters
     */
    public static String getEpochParameters() {
        BlockfrostEndpoint endpoint = createGetEndpoint(EPOCHS_PARAMETERS_URL);
        endpoint.send();

        if (endpoint.getStatusCode() == STATUS_OK) {
            return endpoint.getResponse().getBody();
        } else {
            return JSON.serialize(createErrorResponse(endpoint.getStatusCode(), 'Blockfrost epochs parameters API error'));
        }
    }
    
    /**
     * Submit a transaction to the blockchain
     * @param cborHex The transaction in CBOR hex format
     * @return String transaction hash if successful, or JSON error response
     */
    public static String submitTransaction(String cborHex) {
        if (String.isBlank(cborHex)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException(ERROR_CBOR_REQUIRED);
        }
        
        try {
            HttpRequest req = createSubmitTransactionRequest(cborHex);
            HttpResponse res = new Http().send(req);
            return handleSubmitTransactionResponse(res);
        } catch (Exception e) {
            return JSON.serialize(createErrorResponse('error', 'Network or processing error: ' + e.getMessage(), e.getTypeName()));
        }
    }
    
    /**
     * Get transactions for a specific address
     * @param address The address to query
     * @return String JSON array of transactions
     */
    public static String getAddressTransactions(String address) {
        validateAddress(address);

        String url = ADDRESS_TRANSACTIONS_URL.replace('{address}', address);
        BlockfrostEndpoint endpoint = createGetEndpoint(url);
        endpoint.send();

        if (endpoint.getStatusCode() == STATUS_OK) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == STATUS_NOT_FOUND) {
            return '[]';
        }

        return JSON.serialize(createErrorResponse(endpoint.getStatusCode(), 'Blockfrost address transactions API error'));
    }
    
    /**
     * Get transaction details by hash
     * @param txHash The transaction hash
     * @return String JSON transaction details
     */
    public static String getTransactionDetails(String txHash) {
        if (String.isBlank(txHash)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException(ERROR_TX_HASH_REQUIRED);
        }

        String url = TRANSACTION_DETAILS_URL.replace('{txHash}', txHash);
        BlockfrostEndpoint endpoint = createGetEndpoint(url);
        endpoint.send();

        if (endpoint.getStatusCode() == STATUS_OK) {
            return endpoint.getResponse().getBody();
        } else if (endpoint.getStatusCode() == STATUS_NOT_FOUND) {
            return '{}';
        }

        return JSON.serialize(createErrorResponse(endpoint.getStatusCode(), 'Blockfrost transaction details API error'));
    }
    
    /**
     * Analyze transaction direction for a single transaction
     * @param txHash The transaction hash to analyze
     * @param walletAddresses List of wallet addresses to check against
     * @return String JSON analysis result
     */
    public static String analyzeTransactionDirection(String txHash, List<String> walletAddresses) {
        try {
            if (String.isBlank(txHash)) {
                throw new BlockfrostEndpoint.BlockfrostAPIException(ERROR_TX_HASH_REQUIRED);
            }
            validateWalletAddresses(walletAddresses);
            
            Set<String> walletAddressSet = new Set<String>(walletAddresses);
            String url = TRANSACTION_DETAILS_URL.replace('{txHash}', txHash);
            
            BlockfrostEndpoint endpoint = createGetEndpoint(url);
            endpoint.send();
                
            return handleTransactionAnalysisResponse(endpoint, walletAddressSet);
        } catch (Exception e) {
            return JSON.serialize(createErrorResponse(false, 'Error analyzing transaction direction: ' + e.getMessage()));
        }
    }
    
    /**
     * Analyze transaction directions for multiple transactions
     * @param txHashes List of transaction hashes to analyze
     * @param walletAddresses List of wallet addresses to check against
     * @return String JSON results for all transactions
     */
    public static String analyzeMultipleTransactionDirections(List<String> txHashes, List<String> walletAddresses) {
        try {
            if (txHashes == null || txHashes.isEmpty()) {
                throw new BlockfrostEndpoint.BlockfrostAPIException(ERROR_TX_HASHES_REQUIRED);
            }
            validateWalletAddresses(walletAddresses);
            
            Map<String, Object> results = new Map<String, Object>();
            
            for (String txHash : txHashes) {
                try {
                    String analysis = analyzeTransactionDirection(txHash, walletAddresses);
                    Map<String, Object> analysisMap = parseJsonResponse(analysis);
                    results.put(txHash, analysisMap);
                } catch (Exception e) {
                    results.put(txHash, createErrorResponse(false, 'Failed to analyze transaction: ' + e.getMessage()));
                }
            }
            
            return JSON.serialize(results);
        } catch (Exception e) {
            return JSON.serialize(createErrorResponse(false, 'Error analyzing multiple transactions: ' + e.getMessage()));
        }
    }
    
    /**
     * Publish a wallet sync event
     * @param walletId The wallet ID
     * @param action The action performed
     */
    public static void publishWalletSyncEvent(Id walletId, String action) {
        WalletSyncEvent__e event = new WalletSyncEvent__e(
            WalletId__c = walletId,
            Action__c = action
        );
        EventBus.publish(event);
    }
    
    // =============================================================================
    // PRIVATE HELPER METHODS
    // =============================================================================
    
    /**
     * Create a standard GET endpoint with common headers
     */
    private static BlockfrostEndpoint createGetEndpoint(String url) {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        return new BlockfrostEndpoint()
            .get()
            .setEndpoint(url)
            .setHeaders(new Map<String, String>{
                'Project_id' => projectId,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json'
            });
    }
    
    /**
     * Validate address input
     */
    private static void validateAddress(String address) {
        if (String.isBlank(address)) {
            throw new BlockfrostEndpoint.BlockfrostAPIException(ERROR_INVALID_ADDRESS);
        }
    }
    
    /**
     * Parse JSON response safely
     */
    private static Map<String, Object> parseJsonResponse(String jsonString) {
        return (Map<String, Object>) JSON.deserializeUntyped(jsonString);
    }
    
    /**
     * Extract transaction count from API response
     */
    private static Integer extractTransactionCount(Map<String, Object> totalData) {
        Object txObj = totalData.get('tx_count');
        if (txObj == null) return 0;
        
        if (txObj instanceof Decimal) {
            return ((Decimal) txObj).intValue();
        } else if (txObj instanceof Integer) {
            return (Integer) txObj;
        } else if (txObj instanceof Long) {
            return ((Long) txObj).intValue();
        }
        return 0;
    }
    
    /**
     * Handle asset info API response
     */
    private static Map<String, Object> handleAssetInfoResponse(BlockfrostEndpoint endpoint, String assetId) {
        Integer status = endpoint.getStatusCode();
        String body = endpoint.getResponse().getBody();
        
        if (status == STATUS_OK) {
            try {
                return parseJsonResponse(body);
            } catch (Exception parseError) {
                return createErrorResponse(STATUS_SERVER_ERROR, 'Failed to parse asset data: ' + parseError.getMessage(), body);
            }
        } else if (status == STATUS_NOT_FOUND) {
            return createErrorResponse(STATUS_NOT_FOUND, 'Asset not found', assetId);
        } else {
            return createErrorResponse(status, 'Blockfrost API error', body, assetId);
        }
    }
    
    /**
     * Create HTTP request for transaction submission
     */
    private static HttpRequest createSubmitTransactionRequest(String cborHex) {
        String projectId = AdaWalletsService.getBlockfrostProjectId();
        BlockfrostEndpoint endpoint = new BlockfrostEndpoint().setEndpoint(TRANSACTION_SUBMIT_URL);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint.request.getEndpoint());
        req.setMethod('POST');
        req.setHeader('project_id', projectId);
        req.setHeader('Content-Type', 'application/cbor');
        req.setHeader('Accept', 'application/json');
        req.setBodyAsBlob(EncodingUtil.convertFromHex(cborHex));
        
        return req;
    }
    
    /**
     * Handle transaction submission response
     */
    private static String handleSubmitTransactionResponse(HttpResponse res) {
        if (res.getStatusCode() == STATUS_OK) {
            return extractTransactionHash(res.getBody());
        } else {
            return JSON.serialize(createSubmitTransactionError(res));
        }
    }
    
    /**
     * Extract transaction hash from response
     */
    private static String extractTransactionHash(String responseBody) {
        String txHash = responseBody.trim();
        if (txHash.startsWith('"') && txHash.endsWith('"')) {
            txHash = txHash.substring(1, txHash.length() - 1);
        }
        return txHash;
    }
    
    /**
     * Create error response for transaction submission
     */
    private static Map<String, Object> createSubmitTransactionError(HttpResponse res) {
        String errorBody = res.getBody();
        String errorMessage = parseSubmitTransactionError(errorBody);
        
        return new Map<String, Object>{
            'status' => res.getStatusCode(),
            'error' => errorMessage,
            'raw_response' => errorBody,
            'error_type' => errorBody.contains('BadInputsUTxO') ? 'UTXO_ERROR' : 'GENERAL_ERROR'
        };
    }
    
    /**
     * Parse error message from transaction submission response
     */
    private static String parseSubmitTransactionError(String errorBody) {
        String errorMessage = 'Blockfrost API Error';
        
        try {
            if (String.isNotBlank(errorBody) && errorBody.startsWith('{')) {
                Map<String, Object> errorResponse = parseJsonResponse(errorBody);
                errorMessage = extractErrorMessage(errorResponse);
                
                if (errorMessage.contains('BadInputsUTxO') || errorMessage.contains('UtxoFailure')) {
                    errorMessage = 'UTXO Error: The transaction is trying to spend UTXOs that are invalid, already spent, or do not exist. ' + errorMessage;
                }
            }
        } catch (Exception parseError) {
            // Keep default error message
        }
        
        return errorMessage;
    }
    
    /**
     * Extract error message from error response
     */
    private static String extractErrorMessage(Map<String, Object> errorResponse) {
        if (!errorResponse.containsKey('error')) return 'Blockfrost API Error';
        
        Object errorObj = errorResponse.get('error');
        if (errorObj instanceof String) {
            return (String) errorObj;
        } else if (errorObj instanceof Map<String, Object>) {
            Map<String, Object> errorMap = (Map<String, Object>) errorObj;
            if (errorMap.containsKey('message')) {
                return String.valueOf(errorMap.get('message'));
            }
        }
        return 'Blockfrost API Error';
    }
    
    /**
     * Validate wallet addresses list
     */
    private static void validateWalletAddresses(List<String> walletAddresses) {
        if (walletAddresses == null || walletAddresses.isEmpty()) {
            throw new BlockfrostEndpoint.BlockfrostAPIException(ERROR_WALLET_ADDRESSES_REQUIRED);
        }
    }
    
    /**
     * Handle transaction analysis API response
     */
    private static String handleTransactionAnalysisResponse(BlockfrostEndpoint endpoint, Set<String> walletAddressSet) {
        if (endpoint.getStatusCode() == STATUS_OK) {
            Map<String, Object> txData = parseJsonResponse(endpoint.getResponse().getBody());
            Map<String, Object> analysis = analyzeTransactionDirectionFromData(txData, walletAddressSet);
            return JSON.serialize(analysis);
        } else if (endpoint.getStatusCode() == STATUS_NOT_FOUND) {
            return JSON.serialize(createErrorResponse(false, 'Transaction not found', STATUS_NOT_FOUND));
        } else {
            return JSON.serialize(createErrorResponse(false, 'Blockfrost API error', endpoint.getStatusCode()));
        }
    }
    
    /**
     * Analyze transaction direction from transaction data
     */
    private static Map<String, Object> analyzeTransactionDirectionFromData(Map<String, Object> txData, Set<String> walletAddresses) {
        try {
            Set<String> walletAddressesLower = normalizeAddresses(walletAddresses);
            
            List<Object> inputs = (List<Object>) txData.get('inputs');
            List<Object> outputs = (List<Object>) txData.get('outputs');
            
            if (inputs == null || outputs == null) {
                return createErrorResponse(false, 'Transaction data missing inputs or outputs');
            }
            
            Set<String> inputAddresses = extractAddressesFromInputsOutputs(inputs);
            Set<String> outputAddresses = extractAddressesFromInputsOutputs(outputs);
            
            TransactionDirection direction = determineTransactionDirection(inputAddresses, outputAddresses, walletAddressesLower);
            
            return createTransactionAnalysisResult(direction, inputAddresses, outputAddresses, walletAddressesLower, txData);
        } catch (Exception e) {
            return createErrorResponse(false, 'Error analyzing transaction data: ' + e.getMessage());
        }
    }
    
    /**
     * Normalize wallet addresses to lowercase
     */
    private static Set<String> normalizeAddresses(Set<String> addresses) {
        Set<String> normalizedAddresses = new Set<String>();
        for (String addr : addresses) {
            if (addr != null) normalizedAddresses.add(addr.toLowerCase());
        }
        return normalizedAddresses;
    }
    
    /**
     * Extract addresses from inputs or outputs
     */
    private static Set<String> extractAddressesFromInputsOutputs(List<Object> inputsOrOutputs) {
        Set<String> addresses = new Set<String>();
        for (Object item : inputsOrOutputs) {
            Map<String, Object> itemMap = (Map<String, Object>) item;
            String address = String.valueOf(itemMap.get('address'));
            if (address != null && address != 'null') {
                addresses.add(address.toLowerCase());
            }
        }
        return addresses;
    }
    
    /**
     * Determine transaction direction based on addresses
     */
    private static TransactionDirection determineTransactionDirection(Set<String> inputAddresses, Set<String> outputAddresses, Set<String> walletAddresses) {
        Boolean hasWalletInputs = hasWalletAddresses(inputAddresses, walletAddresses);
        Boolean hasWalletOutputs = hasWalletAddresses(outputAddresses, walletAddresses);
        
        if (hasWalletInputs && hasWalletOutputs) {
            return new TransactionDirection('Internal Transfer', 'Internal', false, false, true);
        } else if (hasWalletOutputs) {
            return new TransactionDirection('Inbound', 'Inbound', true, false, false);
        } else if (hasWalletInputs) {
            return new TransactionDirection('Outbound', 'Outbound', false, true, false);
        } else {
            return new TransactionDirection('External', 'External', false, false, false);
        }
    }
    
    /**
     * Check if any wallet addresses are present in the given address set
     */
    private static Boolean hasWalletAddresses(Set<String> addressSet, Set<String> walletAddresses) {
        for (String addr : addressSet) {
            if (walletAddresses.contains(addr)) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * Create transaction analysis result
     */
    private static Map<String, Object> createTransactionAnalysisResult(TransactionDirection direction, Set<String> inputAddresses, Set<String> outputAddresses, Set<String> walletAddresses, Map<String, Object> txData) {
        return new Map<String, Object>{
            'success' => true,
            'transactionType' => direction.transactionType,
            'direction' => direction.direction,
            'isInbound' => direction.isInbound,
            'isOutbound' => direction.isOutbound,
            'isInternal' => direction.isInternal,
            'inputAddresses' => new List<String>(inputAddresses),
            'outputAddresses' => new List<String>(outputAddresses),
            'walletInputAddresses' => getWalletAddressesInSet(inputAddresses, walletAddresses),
            'walletOutputAddresses' => getWalletAddressesInSet(outputAddresses, walletAddresses),
            'netAmount' => txData.get('netAmount'),
            'netAmountADA' => txData.get('netAmountADA'),
            'totalInputLovelace' => txData.get('totalInputLovelace'),
            'totalOutputLovelace' => txData.get('totalOutputLovelace'),
            'fee' => txData.get('fees'),
            'blockHeight' => txData.get('block_height'),
            'blockTime' => txData.get('block_time'),
            'slot' => txData.get('slot')
        };
    }
    
    /**
     * Get wallet addresses that are present in the given address set
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
     * Create standardized error response
     */
    private static Map<String, Object> createErrorResponse(Object status, String error) {
        return new Map<String, Object>{
            'status' => status,
            'error' => error
        };
    }
    
    private static Map<String, Object> createErrorResponse(Object status, String error, Object additionalData) {
        Map<String, Object> response = createErrorResponse(status, error);
        if (additionalData instanceof String && ((String) additionalData).length() > 0) {
            if (status.equals(STATUS_SERVER_ERROR)) {
                response.put('stackTrace', additionalData);
            } else {
                response.put('rawBody', additionalData);
            }
        }
        return response;
    }
    
    private static Map<String, Object> createErrorResponse(Object status, String error, Object additionalData1, Object additionalData2) {
        Map<String, Object> response = createErrorResponse(status, error, additionalData1);
        if (additionalData2 != null) {
            response.put('assetId', additionalData2);
        }
        return response;
    }
    
    // =============================================================================
    // INNER CLASSES
    // =============================================================================
    
    /**
     * Helper class to represent transaction direction analysis
     */
    private class TransactionDirection {
        public String transactionType;
        public String direction;
        public Boolean isInbound;
        public Boolean isOutbound;
        public Boolean isInternal;
        
        public TransactionDirection(String transactionType, String direction, Boolean isInbound, Boolean isOutbound, Boolean isInternal) {
            this.transactionType = transactionType;
            this.direction = direction;
            this.isInbound = isInbound;
            this.isOutbound = isOutbound;
            this.isInternal = isInternal;
        }
    }
    
    /**
     * Blockfrost platform error representation
     */
    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }
}