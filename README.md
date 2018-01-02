### Description

Source code solution to the [Shopify - Summer 2018 Internship - Backend Challenge](https://backend-challenge-summer-2018.herokuapp.com/).

**NOTE:** Our solution has assumes that sortedness of the output json (ie. top-layer keys & internal child_ids) is not required. This decision was made by design for both convenience and optimization (e.g. prepending menus is more efficient in Elixir than appending them). It would of course be trivial to sort the given output at both layers if needed.

### Prerequisites

This project requires the following Elixir prerequisites to be installed & available in your command-line environment:

  * [Erlang](http://erlang.org/doc/installation_guide/INSTALL.html)
  * [Elixir (>= v1.5.2)](http://elixir-lang.github.io/install.html)

### Setup

From the project directory:

* Install dependencies with `mix deps.get`
* Build the command-line application via `mix escript.build`

### Execution

You should now be able to execute the application via:


       ./shopircruit -c <challenge_id>

where _<challenge_id>_ here would be either 1 or 2 based on the Problem/API specifications given.
