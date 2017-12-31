defmodule Shopircruit.Menus do  
  alias Shopircruit.Gateway
  alias Shopircruit.Parallel

  def retrieve_menus(api_base_url) do
    {first_menus_page, page_count} = api_base_url |> initial_request

    adapted_menu_pages =
      2..page_count
      |> Parallel.pmap(
        fn page_id -> 
          fetch_menus_page(api_base_url, page_id, 0) 
          |> process_raw_menus_page 
        end)
    adapted_menu_pages = [process_raw_menus_page(first_menus_page) | adapted_menu_pages]
    reduce_menu_pages_to_output_json(adapted_menu_pages)
  end

  defp initial_request(api_base_url) do
    api_full_url = api_base_url <> "&page=1"
    response = Gateway.get!(api_full_url)
    json_page = Poison.decode!(response.body)
    case json_page["pagination"] do
      nil -> {nil, nil}
      %{"current_page" => _current_page, "per_page" => per_page, "total" => total_items} ->
        page_count = trunc(Float.ceil(total_items / per_page, 0))
        {json_page["menus"], page_count}
    end
  end

  defp fetch_menus_page(api_base_url, cur_page_id, retry_count) do
    api_full_url = api_base_url <> "&page=#{cur_page_id}"
    response = Gateway.get!(api_full_url)
    json_page = Poison.decode!(response.body)
    case json_page["menus"] do
      [] -> 
        if retry_count <= Gateway.max_retry do
          :timer.sleep(2); fetch_menus_page(api_base_url, cur_page_id, retry_count + 1)
        else
          []
        end
      menus -> menus
    end
  end

  defp process_raw_menus_page(raw_menus_page) do
    raw_menus_page
    |> Enum.reduce(%{}, fn(menu, mapped_menus_page) ->
        menu_id = menu["id"]
        new_children = menu["child_ids"]
        case menu["parent_id"] do
          nil -> Map.put_new(mapped_menus_page, menu_id, %{root_id: menu_id, parent_id: nil, children: new_children})
          parent_id ->
            case Map.get(mapped_menus_page, parent_id) do
              nil ->
                Map.put_new(mapped_menus_page, menu_id, %{root_id: nil, parent_id: nil, children: new_children})
              %{root_id: root_id, parent_id: grandparent, children: prev_children} ->
                map_data = %{root_id: root_id, parent_id: grandparent, children: prev_children ++ new_children}
                Map.update!(mapped_menus_page, parent_id, fn _val -> map_data end )
            end
        end
       end)
  end

  defp resolve_adapted_menus_merge(_key, v1, v2) do
    %{root_id: root_1, parent_id: parent_1, children: children_1} = v1
    %{root_id: root_2, parent_id: parent_2, children: children_2} = v2
    root = if (root_1 == nil), do: root_2, else: root_1
    parent = if (parent_1 == nil), do: parent_2, else: parent_1
    children = children_1 ++ children_2
    %{root_id: root, parent_id: parent, children: children}
  end

  defp find_root_in_data(map, keys, target_key) do
    case keys do
      [] -> nil
      [hd | tl] -> 
        %{root_id: root, parent_id: _parent, children: children} = Map.get(map, hd)
        case children do
          nil -> find_root_in_data(map, tl, target_key)
          _ -> 
            if Enum.member?(children, target_key) do
              if root == nil do
                find_root_in_data(map, Map.keys(map), hd)
              else 
                root
              end
            else
              find_root_in_data(map, tl, target_key)
            end
        end
    end
  end

  defp reduce_merged_data(merged_menus_map) do
    keys = Map.keys(merged_menus_map)
    
    keys
    |> Enum.reduce(%{}, fn(cur_key, result_map) ->
        %{root_id: root, parent_id: _parent, children: children} = Map.get(merged_menus_map, cur_key)
        if (root == cur_key) do
          Map.put_new(result_map, root, children)
        else
          root = if (root == nil), do: find_root_in_data(merged_menus_map, keys, cur_key), else: root
          Map.update(result_map, root, children, fn prev_children -> prev_children ++ children end)
        end
      end)
  end

  defp is_tree_cycle_free(child_ids_list, previously_seen_ids) do
    case child_ids_list do
      [] -> true
      [hd | tail] -> 
        if MapSet.member?(previously_seen_ids, hd) do
          false
        else
          is_tree_cycle_free(tail, MapSet.put(previously_seen_ids, hd))
        end
    end
  end

  defp transform_to_output_format(reduced_menus_map) do
    Map.keys(reduced_menus_map)
    |> Enum.reduce(%{"valid_menus" => [], "invalid_menus" => []}, fn(key, result_map) ->
        child_ids_list = Map.get(reduced_menus_map, key)
        output_menu = %{"root_id" => key, "children" => child_ids_list}
        case is_tree_cycle_free(child_ids_list, MapSet.new([key])) do
          false -> 
            Map.update!(result_map, "invalid_menus", fn existing_menus -> [output_menu | existing_menus] end)
          true ->
            Map.update!(result_map, "valid_menus", fn existing_menus -> [output_menu | existing_menus] end)
        end
       end)
  end

  defp reduce_menu_pages_to_output_json(adapted_menu_pages) do
    adapted_menu_pages
    |> Enum.reduce(fn(page, acc) -> Map.merge(acc, page, &(resolve_adapted_menus_merge/3)) end)
    |> reduce_merged_data
    |> transform_to_output_format
    |> Poison.encode!
    |> IO.puts
  end
end