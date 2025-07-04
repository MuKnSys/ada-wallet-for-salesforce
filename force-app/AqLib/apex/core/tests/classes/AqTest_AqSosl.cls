/*
 * Copyright (c) 2023, Aquiva Labs LLC. All rights reserved.
 *
 *
 * Redistribution and use in source and binary forms, with or without modification,
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

//Unit tests for AqSosl.cls
@IsTest
private with sharing class AqTest_AqSosl {

    private static final Integer SEARCH_RESULTS_LIMIT = 200;

    @IsTest
    private static void testAssembleSoslQuery() {

        String condition = 'Name != null';
        String sorting = 'Name ASC';
        List<String> fields = new List<String>{'Id', 'Name', 'RequiredText__c'};
        String fieldsString = String.join(fields, AqString.COMMA);
        String objectName = TestObject__c.getSObjectType().getDescribe().getName();

        AqSosl sosl = new AqSosl()
            .setSearchObjects(new List<String>{objectName})
            .setFieldsForObject(objectName, fields)
            .setLimitForObject(objectName, SEARCH_RESULTS_LIMIT)
            .setConditionForObject(objectName, condition)
            .setOrderByForObject(objectName, new List<String> { sorting });

        String searchObjectString = sosl.getSearchObjectsAsString();
        Set<String> objects = sosl.getSearchObjects();

        String searchString = objectName + ' (' + fieldsString + ' WHERE ' + condition + '  ORDER BY ' + sorting + '  LIMIT ' + SEARCH_RESULTS_LIMIT + ')';
        System.assertEquals(searchString, searchObjectString);
        System.assertEquals(new Set<String> {objectName}, objects);
    }

    @IsTest
    private static void testSoslSearchResults() {
        List<TestObject__c> recordsToInsert = new List<TestObject__c> {
            new TestObject__c(
                Name = 'Record 1', RequiredText__c = 'Required 1', Checkbox__c = true,
                Date__c = Date.newInstance(2017, 01, 01), Text__c = 'bar'
            ),
            new TestObject__c(
                Name = 'Record 2', RequiredText__c = 'Required 2', Checkbox__c = false,
                Date__c = Date.newInstance(2017, 01, 01), Text__c = 'bar'
            )
        };
        insert recordsToInsert;

        String condition = 'Name != null';
        List<String> fields = new List<String>{'Id'};
        String objectName = TestObject__c.getSObjectType().getDescribe().getName();

        AqSosl sosl = new AqSosl()
            .setSearchObjects(new List<String>{objectName})
            .setSearchScope(AqSosl.Scope.NAME_FIELDS)
            .setFieldsForObject(objectName, fields)
            .setConditionForObject(objectName, condition);

        Test.setFixedSearchResults(new List<Id>(Aq.getIdSet(recordsToInsert, TestObject__c.Id)));

        List<SObject> results = sosl.find('Record').getResultsForObject(objectName);

        System.assertEquals(recordsToInsert.size(), results.size(), 'All records should be returned');
        System.assertEquals(recordsToInsert[0].Id, results[0].Id, 'Correct records should be found');
        System.assertEquals(1, sosl.getResults().size(), 'Results for one object should be returned');
    }

    @IsTest
    private static void testQueryBuilderWithUserMode() {

        String condition = 'Name != null';
        List<String> fields = new List<String>{'Id'};
        String objectName = TestObject__c.getSObjectType().getDescribe().getName();

        AqSosl sosl = new AqSosl()
            .setSearchObjects(new List<String>{objectName})
            .setSearchScope(AqSosl.Scope.NAME_FIELDS)
            .setFieldsForObject(objectName, fields)
            .setConditionForObject(objectName, condition);

        String soslQueryWithUserMode = sosl.getSoslQuery('test');
        Assert.isTrue(soslQueryWithUserMode.containsIgnoreCase('WITH USER_MODE'),
            'Query should contain WITH USER_MODE keywords');
    }

    @IsTest
    private static void testQueryBuilderWithoutUserMode() {

        String condition = 'Name != null';
        List<String> fields = new List<String>{'Id'};
        String objectName = TestObject__c.getSObjectType().getDescribe().getName();

        AqSosl sosl = new AqSosl()
            .setSearchObjects(new List<String>{objectName})
            .setSearchScope(AqSosl.Scope.NAME_FIELDS)
            .setFieldsForObject(objectName, fields)
            .setConditionForObject(objectName, condition)
            .withoutUserMode();

        String soslQueryWithoutUserMode = sosl.getSoslQuery('test');
        Assert.isFalse(soslQueryWithoutUserMode.containsIgnoreCase('WITH USER_MODE'),
            'Query should not contain WITH USER_MODE keywords');
    }

}
