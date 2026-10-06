defmodule MclKanban.ServiceTest do
  # The mcl_om service contract, asserted locally.
  use ExUnit.Case, async: true

  alias MclKanban.Service

  @procedures ~w(claim_next_card claim_card unblock_card release_card block_card finish_card
                 queue_card tag_card untag_card link_card unlink_card comment_on_card
                 prioritise_card reserve_card get_boards get_board_by_repo get_card_by_id
                 get_my_cards enlist_agent discharge_agent open_board withdraw_card)

  test "the service module declares the mcl_om behaviour" do
    behaviours =
      Service.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

    assert :mcl_om_service in behaviours
  end

  test "info names the service and reports the application's own version" do
    {:ok, vsn} = :application.get_key(:mcl_kanban, :vsn)
    assert %{name: "mcl-kanban", version: version, description: d} = Service.info()
    assert version == to_string(vsn)
    assert is_binary(d) and d != ""
  end

  test "every procedure in the design is advertised, each with a handler" do
    names = Enum.map(Service.capabilities(), & &1.name)

    for p <- @procedures do
      assert p in names, p
    end

    for cap <- Service.capabilities() do
      assert %{version: 1, handler: {module, []}, auth: :open} = cap
      assert Code.ensure_loaded?(module), inspect(module)
      assert function_exported?(module, :handle_request, 2)
    end
  end

  test "first iteration: no procedure demands a sealed call (Raf, #2)" do
    for cap <- Service.capabilities() do
      refute Map.get(cap, :confidential) == :required, cap.name
    end
  end

  test "the store the service opens is the one evoq dispatches to" do
    assert %{id: id, dir: dir, mode: :single} = Service.event_store()
    assert id == Application.fetch_env!(:evoq, :store_id)
    assert is_list(dir)
  end

  test "the service does not export the store callbacks mcl_om stopped honouring" do
    refute function_exported?(Service, :store_id, 0)
    refute function_exported?(Service, :data_dir, 0)
  end

  test "the scope is the org; the service asks for no topics" do
    assert %{scope: "mcl-kanban", resources: [], ttl_days: 30} = Service.identity_spec()
  end
end
