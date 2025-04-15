@isTest
public with sharing class BlockfrostServiceHttpCalloutMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {        
        HttpResponse response = new HttpResponse();        
        response.setBody(JSON.serialize('TestConfig'));
        response.setStatusCode(200);
        return response;
    }
}