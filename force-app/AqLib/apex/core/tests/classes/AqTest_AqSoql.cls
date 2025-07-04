/**
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

//Unit tests for AqSoql.cls
@IsTest
private with sharing class AqTest_AqSoql {

    @TestSetup
    private static void setup() {
        AqTest.setup();

        System.runAs(AqTest.adminUser) {

            //Generate test records to query for
            List<TestObject__c> recordsToInsert = new List<TestObject__c>{
                new TestObject__c(
                    Name = 'Record 1', RequiredText__c = 'Required 1', Checkbox__c = true,
                    Date__c = Date.newInstance(2017, 01, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Name = 'Record 2', RequiredText__c = 'Required 2', Checkbox__c = false,
                    Date__c = Date.newInstance(2017, 01, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Name = 'Record 3', RequiredText__c = 'Required 3', Checkbox__c = true,
                    Date__c = Date.newInstance(2017, 03, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Name = 'Record 4', RequiredText__c = 'Required 4', Checkbox__c = false,
                    Date__c = Date.newInstance(2017, 04, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Name = 'Other 5', RequiredText__c = 'Required 5', Checkbox__c = false,
                    Date__c = Date.newInstance(2017, 05, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Name = 'Record 6', RequiredText__c = 'Required 6', Checkbox__c = false,
                    Date__c = null, Text__c = 'bar'
                )
            };

            insert recordsToInsert;

            List<TestObject__c> subRecordsToInsert = new List<TestObject__c>{
                new TestObject__c(
                    Lookup__c = recordsToInsert[0].Id, Name = 'SubRecord 1', RequiredText__c = 'Required 1',
                    Checkbox__c = true, Date__c = Date.newInstance(2017, 01, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Lookup__c = recordsToInsert[0].Id, Name = 'SubRecord 2', RequiredText__c = 'Required 2',
                    Checkbox__c = true, Date__c = Date.newInstance(2017, 01, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Lookup__c = recordsToInsert[1].Id, Name = 'SubRecord 3', RequiredText__c = 'Required 3',
                    Checkbox__c = true, Date__c = Date.newInstance(2017, 03, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Lookup__c = recordsToInsert[1].Id, Name = 'SubRecord 4', RequiredText__c = 'Required 4',
                    Checkbox__c = true, Date__c = Date.newInstance(2017, 04, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Lookup__c = recordsToInsert[2].Id, Name = 'SubRecord 5', RequiredText__c = 'Required 5',
                    Checkbox__c = true, Date__c = Date.newInstance(2017, 05, 01), Text__c = 'bar'
                ),
                new TestObject__c(
                    Lookup__c = recordsToInsert[3].Id, Name = 'SubRecord 6', RequiredText__c = 'Required 6',
                    Checkbox__c = true, Date__c = Date.newInstance(2017, 06, 01), Text__c = 'bar'
                )
            };

            insert subRecordsToInsert;
        }
    }

    @IsTest
    private static void testGetBaseSoql() {
        System.runAs(AqTest.adminUser) {
            List<SObject> records = Database.query(
                AqSoql.getBaseSoql(TestObject__c.getSObjectType(), new Set<String>{
                    'Id', 'Name', 'RequiredText__c'
                })
            );

            System.assertEquals(12, records.size());
            SObject sObj = records[0];
            Map<String, Object> fieldsMap = sObj.getPopulatedFieldsAsMap();
            System.assertEquals(3, fieldsMap.size());
            System.assert(fieldsMap.keySet().containsAll(new Set<String>{
                'Id', 'Name', Aq.appendPrefix('RequiredText__c')
            }));

            AqSoql subSoql = new AqSoql(TestObject__c.Lookup__c, TestObject__c.getSObjectType())
                .withColumns(new List<String>{
                    'Name', 'RequiredText__c'
                });

            List<SObject> recordsWithSubselect = Database.query(
                AqSoql.getBaseSoql(
                    TestObject__c.getSObjectType(),
                    new List<String>{
                        'Id', 'Name', 'RequiredText__c'
                    },
                    new List<AqSoql>{
                        subSoql
                    }
                )
            );
            System.assertEquals(12, recordsWithSubselect.size());
        }
    }

    @IsTest
    private static void testQueryBuilder() {
        System.runAs(AqTest.adminUser) {
            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withColumns(new List<String>{
                    'Id', 'Name', 'RequiredText__c'
                })
                .withWhere('Lookup__c != null');
            List<TestObject__c> records = (List<TestObject__c>) Database.query(soql.getQueryString());
            System.assertEquals(6, records.size());

            soql = soql.withOrderBy(new List<String>{
                'Date__c DESC', 'Name'
            });
            records = (List<TestObject__c>) Database.query(soql.getQueryString());
            System.assertEquals(6, records.size());
            System.assertEquals('SubRecord 6', records[0].Name);
            System.assertEquals('SubRecord 1', records[4].Name);

            soql = soql.withRowLimit(2).withoutSecurityEnforced();
            records = (List<TestObject__c>) Database.query(soql.getQueryString());
            System.assertEquals(2, records.size());
        }
    }

    @IsTest
    private static void testSubSelect() {
        System.runAs(AqTest.adminUser) {
            AqSoql subSoql = new AqSoql(TestObject__c.Lookup__c, TestObject__c.getSObjectType())
                .withColumns(new List<String>{
                    'Name', 'RequiredText__c'
                });

            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withColumns(new List<String>{
                    'Id', 'Name', 'RequiredText__c'
                })
                .withSubSelects(new List<AqSoql>{
                    subSoql
                })
                .withWhere('Lookup__c = null AND Date__c != null')
                .withOrderBy(new List<String>{
                    'Date__c', 'Name'
                });

            List<TestObject__c> records = (List<TestObject__c>) Database.query(soql.getQueryString());
            System.assertEquals(5, records.size());
            System.assertEquals('Record 1', records[0].Name);
            System.assertEquals(2, records[0].AquivaTestObjects__r.size());
        }
    }

    @IsTest
    private static void testSubSelectForAccountContactRelation() {
        System.runAs(AqTest.adminUser) {
            Account accountToInsert = new Account(Name = 'TestAccount');
            insert accountToInsert;

            List<Contact> contactsWithAccountRelation = new List<Contact>{
                new Contact(LastName = 'TestContact1', AccountId = accountToInsert.Id),
                new Contact(LastName = 'TestContact2', AccountId = accountToInsert.Id),
                new Contact(LastName = 'TestContact3', AccountId = accountToInsert.Id)
            };
            insert contactsWithAccountRelation;

            AqSoql subSoql = new AqSoql(Contact.AccountId, Contact.getSObjectType())
                .withColumns(new List<String>{
                    Contact.Name.getDescribe().getName()
                });

            AqSoql soql = new AqSoql(Account.getSObjectType())
                .withColumns(new List<String>{
                    Account.Name.getDescribe().getName()
                })
                .withSubSelects(new List<AqSoql>{
                    subSoql
                })
                .withWhere('Id = \'' + accountToInsert.Id + '\'');

            Account accountRecord = (Account) Database.query(soql.getQueryString());
            System.assertEquals(accountToInsert.Name, accountRecord.Name);
            System.assertEquals(contactsWithAccountRelation.size(), accountRecord.Contacts.size());
        }
    }

    @IsTest
    private static void testCountQuery() {
        System.runAs(AqTest.adminUser) {
            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withWhere('RequiredText__c = \'Required 2\'');

            Integer numberOfRequired2Records = soql.countQuery();

            System.assertEquals(2, numberOfRequired2Records);
        }
    }

    @IsTest
    private static void testAggregatedQuery() {
        System.runAs(AqTest.adminUser) {
            AqAggregation ag = AqAggregation.max(TestObject__c.Date__c, 'alias');

            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withAggregation(new List<AqAggregation>{
                    ag
                });

            List<AggregateResult> results = (List<AggregateResult>) Database.query(soql.getQueryString());
            System.assertEquals(1, results?.size());
            System.assertEquals(Date.newInstance(2017, 06, 01), results[0].get(ag.getAlias()));
        }
    }

    @IsTest
    private static void testAggregatedQueryGroupBy() {
        System.runAs(AqTest.adminUser) {
            AqAggregation ag = AqAggregation.max(TestObject__c.Date__c, 'alias');

            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withAggregation(new List<AqAggregation>{
                    ag
                })
                .withGroupBy(new List<String>{
                    'Lookup__c'
                });

            List<AggregateResult> results = soql.aggregate();
            System.assertEquals(5, results?.size());
            for (AggregateResult res : results) {
                if (res.get(Aq.appendPrefix('Lookup__c')) == null) {
                    System.assertEquals(Date.newInstance(2017, 05, 01), res.get(ag.getAlias()));
                }
            }
        }
    }

    @IsTest
    private static void testMultiAggregationQuery() {
        System.runAs(AqTest.adminUser) {

            List<String> groupingFields = new List<String>{
                Aq.appendPrefix('Lookup__c')
            };
            AqAggregation maxDate = AqAggregation.max(TestObject__c.Date__c, 'maxDate');
            AqAggregation minDate = AqAggregation.min(TestObject__c.Date__c, 'minDate');

            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withAggregation(new List<AqAggregation>{
                    maxDate, minDate
                })
                .withGroupBy(groupingFields);

            List<AggregateResult> results = soql.aggregate();
            System.assertEquals(5, results?.size());
            for (AggregateResult res : results) {
                if (res.get(groupingFields[0]) == null) {
                    System.assertEquals(Date.newInstance(2017, 05, 01), res.get(maxDate.getAlias()));
                    System.assertEquals(Date.newInstance(2017, 01, 01), res.get(minDate.getAlias()));
                }
            }
        }
    }

    @IsTest
    private static void testSecurityModeApplication() {
        System.runAs(AqTest.adminUser) {
            AqSoql soql = new AqSoql(TestObject__c.getSObjectType())
                .withColumns(new List<String>{
                    'Id', 'Name', 'RequiredText__c'
                })
                .withWhere('Lookup__c = null AND Date__c != null');

            soql.withoutSecurityEnforced();
            Assert.isFalse(soql.getQueryString().containsIgnoreCase('WITH'),
                'Should not contain clause related to security enforcement');

            soql.withSecurityEnforced();
            Assert.isTrue(soql.getQueryString().containsIgnoreCase('WITH SECURITY_ENFORCED'),
                'Query should contain clause related to security enforcement');

            soql.withUserMode();
            Assert.isTrue(soql.getQueryString().containsIgnoreCase('WITH USER_MODE'),
                'Query should contain clause related to user mode');

            soql.withoutSecurityEnforced();
            Assert.isFalse(soql.getQueryString().containsIgnoreCase('WITH'),
                'Should not contain clause related to security enforcement');
        }
    }
}