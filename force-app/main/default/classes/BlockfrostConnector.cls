public with sharing class BlockfrostConnector {
    // Static constants for API configuration
    private static final String BASE_URL = 'https://cardano-mainnet.blockfrost.io/api/v0';
    private static final String BLOCKS_LATEST_ENDPOINT = '/blocks/latest';
    private static final String ADDRESS_TOTAL_ENDPOINT = '/addresses/{address}/total';
    private static final Integer REQUEST_TIMEOUT = 120000; // 2 minutes timeout
    private static final String HTTP_METHOD_GET = 'GET';
    private static final String PROJECT_ID_HEADER = 'project_id';
    private static final String TYPE_RECEIVING = '0';
    private static final String TYPE_CHANGE = '1';

    // Helper method to get Blockfrost Project ID
    private static String getBlockfrostProjectId() {
        try {
            String projectId = AdaWalletsService.getBlockfrostProjectId();
            if (String.isBlank(projectId)) {
                System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Blockfrost Project ID is not set or found.');
                throw new AuraHandledException('Blockfrost Project ID is not set or found. Please configure the project ID in the wallet service.');
            }
            System.debug('BlockfrostConnector: Retrieved Project ID successfully');
            return projectId;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Error retrieving Blockfrost Project ID: ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve Blockfrost Project ID: ' + e.getMessage());
        }
    }

    // Generic method to make HTTP requests to Blockfrost API
    private static HttpResponse makeBlockfrostRequest(String endpoint, String method, String projectId) {
        try {
            System.debug('BlockfrostConnector: Making request to endpoint: ' + endpoint);
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(BASE_URL + endpoint);
            request.setMethod(method);
            request.setHeader(PROJECT_ID_HEADER, projectId);
            request.setTimeout(REQUEST_TIMEOUT);

            HttpResponse response = http.send(request);
            System.debug('BlockfrostConnector: Received response status: ' + response.getStatusCode());
            // Allow 404 for isAddressUsed to handle unused addresses
            if (response.getStatusCode() != 200 && response.getStatusCode() != 404) {
                System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: API response: ' + response.getBody());
                throw new AuraHandledException('Blockfrost API Call Failed: ' + response.getStatus() + ' - ' + response.getBody());
            }
            return response;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Error in API request to ' + endpoint + ': ' + e.getMessage());
            throw new AuraHandledException('Error in Blockfrost API request: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String testBlockfrostConfig() {
        try {
            String projectId = getBlockfrostProjectId();
            HttpResponse response = makeBlockfrostRequest(BLOCKS_LATEST_ENDPOINT, HTTP_METHOD_GET, projectId);
            return response.getBody();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Error testing config: ' + e.getMessage());
            throw new AuraHandledException('Error testing Blockfrost config: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Boolean isAddressUsed(String address) {
        try {
            // Validate input
            if (String.isBlank(address)) {
                System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Invalid address provided to isAddressUsed');
                throw new AuraHandledException('Invalid address provided');
            }

            String projectId = getBlockfrostProjectId();
            String endpoint = ADDRESS_TOTAL_ENDPOINT.replace('{address}', address);
            HttpResponse response = makeBlockfrostRequest(endpoint, HTTP_METHOD_GET, projectId);

            // If 404, address doesn't exist on blockchain, so it's unused
            if (response.getStatusCode() == 404) {
                System.debug('BlockfrostConnector: Address ' + address + ' not found, treating as unused');
                return false;
            }

            Map<String, Object> totalData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            
            // Check if the address has any transactions
            Integer txCount = (Integer) totalData.get('tx_count');
            System.debug('BlockfrostConnector: Address ' + address + ' has ' + txCount + ' transactions');
            
            return txCount > 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Error checking address usage: ' + e.getMessage());
            throw new AuraHandledException('Error checking address usage: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> getWalletTotalBalance(String walletId) {
        try {
            // Validate input
            System.debug('BlockfrostConnector: Validating walletId: ' + walletId);
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            // Query all UTXO_Address__c records for the wallet
            System.debug('BlockfrostConnector: Querying UTXO_Address__c for Wallet__c: ' + walletId);
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Address__c, Type__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                AND Type__c IN (:TYPE_RECEIVING, :TYPE_CHANGE)
                WITH SECURITY_ENFORCED
            ];
            System.debug('BlockfrostConnector: Found ' + utxoAddresses.size() + ' UTXO addresses');

            if (utxoAddresses.isEmpty()) {
                throw new AuraHandledException('No UTXO addresses found for Wallet ID: ' + walletId);
            }

            String projectId = getBlockfrostProjectId();
            Map<String, Object> result = new Map<String, Object>();
            Map<String, Map<String, Object>> addressDetails = new Map<String, Map<String, Object>>();
            Map<String, Decimal> totalReceived = new Map<String, Decimal>();
            Map<String, Decimal> totalSent = new Map<String, Decimal>();

            // Fetch total data for each address
            for (UTXO_Address__c addr : utxoAddresses) {
                System.debug('BlockfrostConnector: Processing address: ' + addr.Address__c + ', Type: ' + addr.Type__c);
                String endpoint = ADDRESS_TOTAL_ENDPOINT.replace('{address}', addr.Address__c);
                HttpResponse response;
                try {
                    response = makeBlockfrostRequest(endpoint, HTTP_METHOD_GET, projectId);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Failed to fetch total for address ' + addr.Address__c + ': ' + e.getMessage());
                    continue; // Skip this address and continue with others
                }

                try {
                    Map<String, Object> totalData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    System.debug('BlockfrostConnector: Deserialized response for ' + addr.Address__c + ': ' + JSON.serialize(totalData));

                    // Validate response structure
                    if (!totalData.containsKey('tx_count') || !totalData.containsKey('received_sum') || !totalData.containsKey('sent_sum')) {
                        System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Invalid response structure for ' + addr.Address__c + ': ' + JSON.serialize(totalData));
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
                            System.debug(LoggingLevel.WARN, 'BlockfrostConnector: Skipping invalid asset for ' + addr.Address__c + ': ' + JSON.serialize(asset));
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
                            System.debug(LoggingLevel.WARN, 'BlockfrostConnector: Skipping invalid asset for ' + addr.Address__c + ': ' + JSON.serialize(asset));
                            continue;
                        }
                        Decimal quantity = Decimal.valueOf(quantityStr);
                        totalSent.put(unit, (totalSent.get(unit) != null ? totalSent.get(unit) : 0) + quantity);
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Error processing response for ' + addr.Address__c + ': ' + e.getMessage());
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

            System.debug('BlockfrostConnector: Computed total balance for Wallet__c ' + walletId + ': ' + JSON.serialize(result));
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BlockfrostConnector: Error in getWalletTotalBalance for walletId ' + walletId + ': ' + e.getMessage() + '\nStack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving wallet balance: ' + e.getMessage());
        }
    }
}