// Apex script to update ADA assets
List<UTXO_Asset__c> adaAssets = [SELECT Id, Asset__c, Name__c, Decimals__c FROM UTXO_Asset__c WHERE Asset__c = 'lovelace'];
for (UTXO_Asset__c asset : adaAssets) {
    asset.Asset__c = 'ADA';
    asset.Name__c = 'Cardano';
    asset.Decimals__c = 6;
}
if (!adaAssets.isEmpty()) {
    update adaAssets;
    System.debug('Updated ' + adaAssets.size() + ' ADA asset records.');
} else {
    System.debug('No ADA asset records needed updating.');
} 