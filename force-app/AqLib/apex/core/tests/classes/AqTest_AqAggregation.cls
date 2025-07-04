/**
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
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

//Unit tests for AqAggregation.cls
@isTest
private with sharing class AqTest_AqAggregation {
    
    private static final String AGGR_TEMPLATE = '{0}({1}) {2}';

    @IsTest
    static void testCorrectlyFormatSum() {

        String expectedAlias = 'myAlias';
        String fieldNameWithPrefix = Aq.appendPrefix('RequiredText__c');
        AqAggregation agg = AqAggregation.sum(TestObject__c.RequiredText__c, expectedAlias);
        System.assertEquals(AqString.format(AGGR_TEMPLATE, 'SUM', fieldNameWithPrefix, expectedAlias), agg.toString());
        System.assertEquals(expectedAlias, agg.getAlias());
        System.assertEquals(fieldNameWithPrefix, agg.getFieldName());
    }

    @IsTest
    static void testCorrectlyFormatCountDistinct() {

        String expectedAlias = 'myAlias';
        String fieldNameWithPrefix = Aq.appendPrefix('RequiredText__c');
        AqAggregation agg = AqAggregation.countDistinct(TestObject__c.RequiredText__c, expectedAlias);
        System.assertEquals(AqString.format(AGGR_TEMPLATE, 'COUNT_DISTINCT', fieldNameWithPrefix, expectedAlias), agg.toString());
        System.assertEquals(expectedAlias, agg.getAlias());
    }

    @IsTest
    static void testCorrectlyFormatCount() {

        AqAggregation agg = AqAggregation.count();
        System.assertEquals('COUNT()', agg.toString().trim());
    }
}