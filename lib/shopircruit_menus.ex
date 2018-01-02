defmodule Shopircruit.Menus do  
  alias Shopircruit.Gateway
  alias Shopircruit.Parallel

  # public method to construct solution from data at challenge URI
  def retrieve_menus(api_base_uri) do
    # get first page of menus data
    {first_menus_page, page_count} = api_base_uri |> initial_request

    # adapt menu pages in parallel
    adapted_menu_pages =
      2..page_count
      |> Parallel.pmap(
        fn page_id -> 
          fetch_menus_page(api_base_uri, page_id) 
          |> process_raw_menus_page 
        end)

    # prepend initial adapted menus page to our list (constant time insertion)
    adapted_menu_pages = [process_raw_menus_page(first_menus_page) | adapted_menu_pages]

    # reduce mapped intermediate data to target json format
    reduce_menu_pages_to_output_json(adapted_menu_pages)
  end

  # private helper to get and decode json
  defp get_and_decode_json_request(uri) do
    response = Gateway.get!(uri)
    Poison.decode!(response.body)
  end

  # initial request to paginated api
  defp initial_request(api_base_uri) do
    json_page = api_base_uri <> "&page=1" |> get_and_decode_json_request
    case json_page["pagination"] do
      %{"per_page" => per_page, "total" => total_items} ->
        page_count = trunc(Float.ceil(total_items / per_page, 0))
        {json_page["menus"], page_count}
    end
  end

  # independent request for single json page of menus API
  defp fetch_menus_page(api_base_uri, cur_page_id) do
    api_base_uri <> "&page=#{cur_page_id}" 
    |> get_and_decode_json_request
    |> Map.get("menus")
  end

  # process raw json of menus list for a single page of API
  defp process_raw_menus_page(raw_menus_list) do
    raw_menus_list
    |> Enum.reduce(%{}, fn(node, mapped_menus_page) ->
        node_id = node["id"]
        new_children = node["child_ids"]
        # assumption: (parent_id == nil) => root
        case node["parent_id"] do
          nil -> Map.put_new(mapped_menus_page, node_id, %{root_id: node_id, parent_id: nil, children: new_children})
          parent_id ->
            case Map.get(mapped_menus_page, parent_id) do
              nil ->
                Map.put_new(mapped_menus_page, node_id, %{root_id: nil, parent_id: nil, children: new_children})
              %{root_id: root_id, parent_id: grandparent, children: prev_children} ->
                map_data = %{root_id: root_id, parent_id: grandparent, children: prev_children ++ new_children}
                Map.update!(mapped_menus_page, parent_id, fn _val -> map_data end )
            end
        end
       end)
  end

  # resolve conflict in merging intermediate maps
  defp resolve_adapted_menus_merge(_key, v1, v2) do
    %{root_id: root_1, parent_id: parent_1, children: children_1} = v1
    %{root_id: root_2, parent_id: parent_2, children: children_2} = v2
    root = if (root_1 == nil), do: root_2, else: root_1
    parent = if (parent_1 == nil), do: parent_2, else: parent_1
    children = children_1 ++ children_2
    %{root_id: root, parent_id: parent, children: children}
  end

  # reduce adapted map to convey target data
  defp reduce_merged_data(merged_menus_map) do
    keys = Map.keys(merged_menus_map)
    
    # construct result_map in O(n) by tracking roots and growing children for each encountered node
    Enum.reduce(keys, {%{}, %{}}, fn(cur_key, {result_map, node_to_root_map}) ->
        %{root_id: root, parent_id: _parent, children: children} = Map.get(merged_menus_map, cur_key)
        if (root == cur_key) do
          result_map = Map.put_new(result_map, root, children)
          node_to_root_map = Map.put_new(node_to_root_map, root, root)
          node_to_root_map = children |> Enum.reduce(node_to_root_map, fn child_id, acc -> Map.put(acc, child_id, root) end)
          {result_map, node_to_root_map}
        else
          root = if (root == nil), do: Map.get(node_to_root_map, cur_key), else: root
          result_map = Map.update(result_map, root, children, fn prev_children -> prev_children ++ children end)
          node_to_root_map = children |> Enum.reduce(node_to_root_map, fn child_id, acc -> Map.put(acc, child_id, root) end)
          {result_map, node_to_root_map}
        end
      end)
    |> elem(0)
  end

  # check if menus tree contains cycle (*root must initially be in previously_seen_ids*)
  defp is_tree_cycle_free?(child_ids_list, previously_seen_ids) do
    case child_ids_list do
      [] -> true
      [hd | tail] -> 
        if MapSet.member?(previously_seen_ids, hd) do
          false
        else
          is_tree_cycle_free?(tail, MapSet.put(previously_seen_ids, hd))
        end
    end
  end

  # transform adapted data to output json format
  defp transform_to_output_format(reduced_menus_map) do
    Map.keys(reduced_menus_map)
    |> Enum.reduce(%{"valid_menus" => [], "invalid_menus" => []}, fn(key, result_map) ->
        child_ids_list = Map.get(reduced_menus_map, key)
        output_menu = %{"root_id" => key, "children" => child_ids_list}
        case is_tree_cycle_free?(child_ids_list, MapSet.new([key])) do
          false -> 
            Map.update!(result_map, "invalid_menus", fn existing_menus -> [output_menu | existing_menus] end)
          true ->
            Map.update!(result_map, "valid_menus", fn existing_menus -> [output_menu | existing_menus] end)
        end
       end)
  end

  # routine to reduce json pages to output format
  defp reduce_menu_pages_to_output_json(adapted_menu_pages) do
    adapted_menu_pages
    |> Enum.reduce(fn(page, acc) -> Map.merge(acc, page, &(resolve_adapted_menus_merge/3)) end)
    |> reduce_merged_data
    |> transform_to_output_format
    |> Poison.encode!
    |> IO.puts
  end
end