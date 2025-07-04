/*
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

//Unit tests for AqJson.cls.
@isTest
private with sharing class AqTest_AqJson {

    //Use to test all token types
    private class TestClass {

        public String NullString = null;
        public String StringValue = 'Foo';
        public Integer IntegerValue = 5;
        public Decimal DecimalValue = 5.5;
        public Boolean TrueValue = true;
        public Boolean FalseValue = false;
        public SubClass SubValue = new SubClass();
        public List<SubClass> SubList = new List<SubClass>{new SubClass()};

    }

    private class SubClass {

        public String StringValue = 'Bar';

    }

    //stripNulls()
    @isTest
    private static void testStripNulls() {

        TestClass target = new TestClass();
        String jsonString = JSON.serialize(target);
        String stripped = AqJson.stripNulls(jsonString, true);

        //Verify stripped still equals original
        System.assertEquals(JSON.serialize(JSON.deserialize(stripped, TestClass.class)), jsonString);

    }

}
