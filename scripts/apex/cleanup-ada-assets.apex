// Apex script to update ADA assets
List<UTXO_Asset__c> adaAssets = [SELECT Id, Unit__c, Name__c, Decimals__c FROM UTXO_Asset__c WHERE Unit__c = 'lovelace'];
for (UTXO_Asset__c asset : adaAssets) {
    asset.Unit__c = 'ADA';
    asset.Name__c = 'Cardano';
    asset.Decimals__c = 6;
}
if (!adaAssets.isEmpty()) {
    update adaAssets;
    System.debug('Updated ' + adaAssets.size() + ' ADA asset records.');
} else {
    System.debug('No ADA asset records needed updating.');
} 