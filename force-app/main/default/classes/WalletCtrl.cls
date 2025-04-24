public with sharing class WalletCtrl {
    // Static constants for address types
    private static final String TYPE_RECEIVING = '0';
    private static final String TYPE_CHANGE = '1';

    @AuraEnabled(cacheable=true)
    public static String getPaymentAddress(String walletId) {
        try {
            // Validate input
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            // Query UTXO_Address__c records for the given Wallet__c with Type__c = '0' (receiving)
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getUTXOAddressesByWalletIdAndTypeOrdered(walletId, TYPE_RECEIVING);

            // Check if any records were found
            if (utxoAddresses.isEmpty()) {
                throw new AuraHandledException('No receiving address found for Wallet ID: ' + walletId);
            }

            // Find the first unused address
            String paymentAddress = null;
            for (UTXO_Address__c addr : utxoAddresses) {
                Boolean isUsed = BlockfrostService.isAddressUsed(addr.Address__c);
                if (!isUsed) {
                    paymentAddress = addr.Address__c;                    
                    break;
                }
            }

            // If no unused address is found, throw an exception
            if (paymentAddress == null) {
                throw new AuraHandledException('No unused receiving address found for Wallet ID: ' + walletId);
            }

            return paymentAddress;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving payment address: ' + e.getMessage());
        }
    }

    @AuraEnabled()
    public static Map<String, Object> getWalletTotalBalance(String walletId) {
        try {            
            return BlockfrostService.getWalletTotalBalance(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to check is address used: ' + e.getMessage());
        }
    }
}