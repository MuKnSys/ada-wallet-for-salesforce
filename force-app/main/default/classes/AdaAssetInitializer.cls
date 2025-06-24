public with sharing class AdaAssetInitializer {
    public class AssetRecord {
        public String symbol;
        public String name;
        public String exchange;
        public String coingecko;
    }

    @AuraEnabled
    public static void initializeAssets() {
        try {
            StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = 'ADAAssets' LIMIT 1];
            String jsonString = sr.Body.toString();
            List<AssetRecord> assets = (List<AssetRecord>) JSON.deserialize(jsonString, List<AssetRecord>.class);

            Set<String> names = new Set<String>();
            for (AssetRecord ar : assets) {
                names.add(ar.name);
            }

            Map<String, Asset__c> existingMap = new Map<String, Asset__c>();
            for (Asset__c a : [SELECT Id, Name, Asset_Name__c FROM Asset__c WHERE Asset_Name__c IN :names]) {
                existingMap.put(a.Asset_Name__c, a);
            }

            List<Asset__c> toInsert = new List<Asset__c>();
            List<Asset__c> toUpdate = new List<Asset__c>();
            for (AssetRecord rec : assets) {
                if (String.isBlank(rec.name)) continue;
                if (existingMap.containsKey(rec.name)) {
                    Asset__c upd = existingMap.get(rec.name);
                    upd.Name = rec.symbol == null ? rec.name : rec.symbol;
                    upd.Asset_Name__c = rec.name;
                    toUpdate.add(upd);
                } else {
                    Asset__c ins = new Asset__c();
                    ins.Name = rec.symbol == null ? rec.name : rec.symbol;
                    ins.Asset_Name__c = rec.name;
                    toInsert.add(ins);
                }
            }
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Asset initialization failed: ' + e.getMessage());
        }
    }
} 