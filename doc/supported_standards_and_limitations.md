# Features, Supported standards and limitations

## Features
- support for both the client and the server side
- generate client module (stubs), server module (skeletons) and data types
  from WSDL ("contract first")
- Generate WSDL from type and function specifications ("contract last")
- XML <--> Erlang data mapping
- pre-integrated with HTTP clients Inets/HTTPC and ibrowse
- pre-integrated with HTTP server Inets/HTTPD, Cowboy (versions 1.* and 2) and Mochiweb
- defined APIs for integration with other HTTP servers/clients
- generation of example messages for easy testing
- support for SOAP with attachments

## Supported standards
The `soap` application supports SOAP communication over HTTP.  

The following standards have been used as the starting points:
- [SOAP 1.1](https://www.w3.org/TR/2000/NOTE-SOAP-20000508/)
- [SOAP 1.2](https://www.w3.org/TR/soap/)
- [SOAP Messages with Attachments](https://www.w3.org/TR/SOAP-attachments)
- [WSDL 1.1](https://www.w3.org/TR/2001/NOTE-wsdl-20010315)
- [WSDL 1.1 Binding extension for SOAP 1.2](https://www.w3.org/Submission/wsdl11soap12/)
- [WSDL 2.0](https://www.w3.org/TR/2007/REC-wsdl20-20070626/) - but only to a limited extent.

The support for these standards is in general limited to [WS-I Basic Profile Version 1.2](http://ws-i.org/profiles/basicprofile-1.2-2010-11-09.html) for
SOAP 1.1 and [WS-I Basic Profile Version 2.0](http://ws-i.org/profiles/BasicProfile-2.0-2010-11-09.html) for SOAP
1.2.

For WSDL 2.0 only SOAP bindings are supported, and only the basic features
have been implemented.


## Limitations
The WS-I basic profiles put a number of restrictions on web services. In
general only web services that comply to the WS-I basic profile are 
supported by the `soap` application.

The most important restrictions from the WS-I basic profile are:
- No support for SOAP encoding (only "literal" encoding) 
- No support for the `soapenc:arrayType`
- Not more than 1 `wsdl:part` in the message body
- WSDL 1.1 must be used to describe the service. (but the `soap` application
  also offers limited support for WSDL 2.0 with SOAP bindings).

The `soap` application uses erlsom for the serialization/de-serialization to and
from XML. This means that the limitations of erlsom also apply. There are a
few XML Schema features that are not supported, and there are some
limitations regarding the data mapping and type checking. These can be found in
the [erlsom documentation](https://github.com/willemdj/erlsom/blob/master/README.md).

