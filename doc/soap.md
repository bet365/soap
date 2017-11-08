# soap Reference #

- [Introduction](#introduction)
- [Data Types](#data-types)
- [Function index](#function-index)

## Introduction ##
The `soap` module provides the API of the `soap` application. It offers
functions to generate a WSDL from Erlang types, to generate Erlang modules
and example values from a WSDL, and to start and stop the generated server.

## Data Types

#### wsdl2erlang_option()
The options that can be passed to `wsdl2erlang\2`, see the function
description for an explanation of these options.

```erlang
wsdl2erlang_option() :: 
  {http_client, atom()} | 
  {http_options, any()} |
  {http_server, atom()} |
  {attachments, boolean()} |
  {automatic_prefixes, boolean()} |
  {test_values, boolean()} |
  {generate_tests, none | client | server | both} |
  {module, string()} |
  {erlsom_options, proplists:proplist()} |
  {generate, client | server | both} |
  {service, string()} |
  {port, string()} }
  {strict, boolean()}.
```
#### elang2wsdl_option()
The options that can be passed to `erlang2wsdl\4`, see the function
description for an explanation of these options.

```erlang
erlang2wsdl_option() :: {target_namespace, string()}.
```

## Function Index
- [wsdl2erlang/1](#wsdl2erlang1)
- [wsdl2erlang/2](#wsdl2erlang2)
- [erlang2wsdl/3](#erlang2wsdl3)
- [erlang2wsdl/4](#erlang2wsdl4)
- [start_server/1](#start_server1)
- [start_server/2](#start_server2)
- [stop_server/1](#stop_server1)
- [stop_server/2](#stop_server2)

### wsdl2erlang/1 ###

```erlang
wsdl2erlang(Filename::string()) -> ok | {error, any()}
```

Equivalent to `wsdl2erlang(Filename, []).`

### wsdl2erlang/2 ###

```erlang
wsdl2erlang(Filename::string(), [wsdl2erlang_option()]) -> ok | {error, any()}
```

Generate a set of modules from a WSDL.

The information that is required to generate the modules is
collected via a simple dialog in the shell. If that is not desirable, this
information can also be provided as options.

The following options are available:

- `{service, Service_name::string()}` - the name of the service for which
  the code must be generated. If the WSDL describes only 1 service this
  parameter can be omitted.

- `{port, Port_name::string()}` - the name of the port for which
  the code must be generated. If there is only one port for the selected
  service this parameter can be omitted.

- `{generate, client | server | both}` - determines which modules will be
  generated. In any case a .hrl file will be generated, with the name
  <Service>.hrl (where <Service> is the name of the Service, see above).

- `{client_name, string()}` - The name of the client module. Defaults to
  <Service>\_client.hrl.

- `{server_name, string()}` - The name of the server module. Defaults to
  <Service>\_server.hrl.

- `{http_client, module()}` - The name of the module that implements the
  HTTP client integration API. The `soap` application provides the following
  modules:
  - `soap_client_ibrowse` - to use [ibrowse](https://github.com/cmullaparthi/ibrowse)
  - `soap_client_inets` - to use the `httpc` module that is included with
    the standard Erlang distribution.

  See [integrating a new http client](#integrating_a_client) for an
  explanation how to add another client.

- `{http_server, module()}` - The name of the module that implements the
  HTTP server integration API. The `soap` application provides the following
  modules:
  - `soap_server_cowboy_1` - to use
    [cowboy](https://github.com/ninenines/cowboy), version 1.0.x
  - `soap_server_cowboy_2` - to use
    [cowboy](https://github.com/ninenines/cowboy), version 2.
  - `soap_server_mochiweb` - to use
    [mochiweb](https://github.com/mochi/mochiweb)
  - `soap_server_inets` - to use the `httpd` module that is included with
    the standard Erlang distribution.

  See [integrating a new http server](#integrating_a_server) for an
  explanation how to add another server.

- `{attachments, boolean()}` - If true, the client module will contain
  functions that can support SOAP attachments (both as a part of the request
  and as a part of the response). Note that the option has no impact on the
  server module: on the server side attachments are accessed via the
  `soap_req`, see [soap_req reference](soap_req.md). 

- `{namespaces, [{Uri::string, Prefix::string() | undefined}]}` - To specify the prefix
  that must be used for the records that are created for the types from a
  namespace (as defined in the `types` section of the WSDL).
  Each namespace must have its own prefix. For one namespace the value
  'undefined' can be used, which means that no prefix will be applied.
  (Note: if the WSDL contains types with names that conflict with names for
  existing types (like `string`), a prefix _must_ be specified, otherwise
  the resulting code will not compile.)

- `{generate_tests, none | client | server | both}` - Depending on the 
  selected value, 0, 1 or 2 additional modules will be
  generated.  These modules will contain stubs ans skeletons with example
  request and response values. They can be used for testing. It can also
  be helpful to have an example of a valid request or response.

  The generated modules will have the same name as the "normal" client and
  server module, but with "\_test" appended.

- `{test_values, boolean()}` - If true, the functions in the
  generated server module (the functions that implement the operations)
  will include test response values. This means that the
  generated server will return values that are in accordance with the type specification in the
  WSDL, in so far as these are supported by erlsom. This can be convenient
  in testing scenarios; it can also be helpful as an example for the
  construction of a response.

  Note that the generated module will be the same (apart from the name) as
  the module that would be created for the server side if the option
  `{generate_tests, server}`  or `{generate_tests, both}` is used.

- `{erlsom_options, proplists:proplist()}` - These options are passed on to
  erlsom. This can for example be used to specify the options for dealing
  with imported namespaces in the `types` (xsd) section of the WSDL. The
  default value for this option is `[{strict, true}]`. 

- `{strict, boolean()}` - If `false`, the functions that decode and encode XML
  will convert only integer (xsd:integer) and boolean values from the XML
  to and from Erlang integer/boolean values (this is the standard Erlsom behaviour). All
  other types will be represented as strings (without testing the
  validity).  (Note that this option can also be set as one of the
  `erlsom_options`, see above. If the two settings conflict, the version
  that is set explicitly prevails over the value that is part of the
  `erlsom_options`).
  
  If `true` (the default for the `soap` application) a number of
  additional data-types will be converted (and checked for validity, hence
  the name 'strict'). This applies for all types derived from integers
  (`int`, `long`, `nonPositiveInteger`, `unsignedLong` etc.), as well as
  `float` and `double`.


### erlang2wsdl/3 ###


```erlang
erlang2wsdl(Hrl_file::string(), Service_name::string(), Url::string()) -> ok.
```

Equivalent to `erlang2wsdl(Hrl_file, Service_name, Url, []).`

### erlang2wsdl/4 ###

```erlang
erlang2wsdl(Hrl_file::string(), Service_name::string(), Url::string(), 
    [erlang2wsdl_option()]) -> ok.
```
Create a WSDL file from a .hrl file that contains the specification of one
or more functions and the types used by these functions.

See [Generating a WSDL](generating_a_wsdl.md) for more information.

### start_server/1 ###

```erlang
start_server(Server::module()) -> {ok, pid()}.
```

Equivalent to `start_server(Server, []).`

### start_server/2 ###

```erlang
start_server(Server::module(), [Option]) -> {ok, pid()}.
```

Starts a generated SOAP server. The Options are passed to the handler
module in the `init` callback (see the [callback
documentation](soap_server_callbacks.md)).

### stop_server/1 ###

```erlang
stop_server(Server::module()) -> ok.
```

Stops the server.
