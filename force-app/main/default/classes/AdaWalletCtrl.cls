public with sharing class AdaWalletCtrl {
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
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Address__c, Index__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                AND Type__c = :TYPE_RECEIVING
                WITH SECURITY_ENFORCED
                ORDER BY Index__c ASC
            ];

            // Check if any records were found
            if (utxoAddresses.isEmpty()) {
                throw new AuraHandledException('No receiving address found for Wallet ID: ' + walletId);
            }

            // Find the first unused address
            String paymentAddress = null;
            for (UTXO_Address__c addr : utxoAddresses) {
                Boolean isUsed = BlockfrostConnector.isAddressUsed(addr.Address__c);
                if (!isUsed) {
                    paymentAddress = addr.Address__c;
                    System.debug('AdaWalletCtrl: Found unused payment address for Wallet__c ' + walletId + ': ' + paymentAddress + ' at Index__c ' + addr.Index__c);
                    break;
                }
            }

            // If no unused address is found, throw an exception
            if (paymentAddress == null) {
                throw new AuraHandledException('No unused receiving address found for Wallet ID: ' + walletId);
            }

            return paymentAddress;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AdaWalletCtrl: Error retrieving payment address for Wallet__c ' + walletId + ': ' + e.getMessage());
            throw new AuraHandledException('Error retrieving payment address: ' + e.getMessage());
        }
    }
}