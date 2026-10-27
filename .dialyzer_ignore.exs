# Dialyzer ignore file (term format, see deps/dialyxir/README.md).
#
# Every entry is a known finding that is not a defect in this repository.
[
  # macula ships its beams without debug_info (a NIF-heavy rebar3 package),
  # so it is excluded from the PLT (`plt_ignore_apps` in mix.exs). Dialyzer
  # then cannot see the callbacks of its behaviours.
  ~r/Callback info about the :macula_response behaviour is not available/,
  ~r/Callback info about the :macula_subscriber behaviour is not available/,
  # For the same reason the signed approvals (#30) call macula's signed
  # objects, node keys and crypto profile untyped from here, and the crew
  # facts (#40) call its topic builders, its CBOR encoder and the direct dial.
  ~r/Function :macula(_(signed_object|node_keys|crypto_profile|topic|record_cbor))?\.[a-z_]+\/\d+ does not exist/,
  ~r/Unknown type: :macula_node_keys\.node_key\/0/,
  # reckon_db is excluded from the PLT for the same reason, so the store
  # wiring's calls into reckon_db_sup and the health probe's call into
  # reckon_db_store are untyped from here.
  ~r/Function :reckon_db_(sup|store)\.[a-z_]+\/\d+ does not exist/
]
