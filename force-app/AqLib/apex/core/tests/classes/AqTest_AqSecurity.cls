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

@IsTest
private with sharing class AqTest_AqSecurity {

    @IsTest
    private static void testAllMethods () {
        TestObject__c rec1 = new TestObject__c(RequiredText__c = 'Foo');
        List<TestObject__c> objList = new List<TestObject__c>{rec1};

        try {
            AqSecurity.checkAccessPermissions(rec1);
            AqSecurity.checkAccessPermissions(objList);

            AqSecurity.checkCreatePermissions(rec1);
            AqSecurity.checkCreatePermissions(objList);

            AqSecurity.checkUpdatePermissions(rec1);
            AqSecurity.checkUpdatePermissions(objList);

            AqSecurity.checkDeletePermissions(rec1);
            AqSecurity.checkDeletePermissions(objList);

            AqSecurity.checkUndeletePermissions(rec1);
            AqSecurity.checkUndeletePermissions(objList);
        } catch (Exception e){
            System.assert(false, 'exception should not be thrown');
        }
    }
}
