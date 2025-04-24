public with sharing class BlockfrostService {
    private static final String BLOCKS_URL = '/blocks/latest';
    private static final String ADDRESS_TOTAL_URL = '/addresses/{address}/total';
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
            
            // Check if the address has any transactions
            Integer txCount = (Integer) totalData.get('tx_count');            
            return txCount > 0;
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

    public class BlockfrostPlatformError {
        public Integer code;
        public String message;
    }
}