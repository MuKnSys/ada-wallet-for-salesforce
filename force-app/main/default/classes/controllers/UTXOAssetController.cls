public with sharing class UTXOAssetController {
    /**
     * Sets Is_Used__c = true for a list of UTXO_Address__c records
     * @param utxoAddressIds List of UTXO Address record IDs
     */
    @AuraEnabled
    public static void setAddressesUsed(List<Id> utxoAddressIds) {
        try {
            UTXOHelper.setAddressesUsed(utxoAddressIds);
        } catch (Exception e) {
            throw new AuraHandledException('Error setting addresses as used: ' + e.getMessage());
        }
    }
} 