%{
  configs: [
    %{
      name: :default,
      files: %{
        included: ["apps/*/lib/", "apps/*/test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true
    }
  ]
}
