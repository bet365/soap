%%
%% %CopyrightBegin%
%%
%% Copyright Hillside Technology Ltd. 2016. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%%
%%% record definitions for SOAP faults
%%%

-record(faultdetail, {uri :: string(),
                      tag :: string(),
                      text :: string()}).

-record(faultcode, {uri :: string() | undefined,
                    code :: string() | atom(),
                    subcode :: #faultcode{} | undefined % only v. 1.2
                   }).

-record(faultreason, {text :: string(),
                      language :: string()}).

-record(soap_fault_1_1, {faultcode :: #faultcode{},
                         faultstring :: string(),
                         faultactor :: string(),
                         detail :: [#faultdetail{}]}).

-record(soap_fault_1_2, {code :: #faultcode{},
                         reason :: [#faultreason{}],
                         role :: string(),
                         detail :: [#faultdetail{}]}).
