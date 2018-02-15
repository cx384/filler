filler = {}
filler.blacklist = {}
filler.endless_placeable = {}
filler.placing_from_top_to_bottom = {}
filler.blacklist["protector:protect"] = true
filler.blacklist["protector:protect2"] = true
--filler.endless_placeable["air"] = true
--filler.endless_placeable["default:water_source"] = true

filler.placing_from_top_to_bottom["air"] = true

local max_volume = 32^3
local color_pos1 = "#ffbb00"
local color_pos2 = "#00bbff"
local speed = 0.1
local sound_placing_failed = "default_item_smoke" --"default_cool_lava" --"default_tool_breaks"
local sound_set_pos = "default_place_node_hard"
local sound_scan_node = "default_dig_metal"
local marker_time = 4
local ownercheck = false  -- set to true makes the device belonging to one user only (anti_griefing)
local recipe_on = true   -- tool can be crafted

local mod_storage = minetest.get_mod_storage()

local function add_rollback_storage(player, pos, node)
	local t = minetest.deserialize(mod_storage:get_string(player.."_rollback_storage")) or {}
	table.insert(t, 1, {pos = pos, node = node})
	mod_storage:set_string(player.."_rollback_storage", minetest.serialize(t))
end

local function get_rollback_storage(player)
	local t = minetest.deserialize(mod_storage:get_string(player.."_rollback_storage")) or {}
	local e = table.remove(t, 1)
	mod_storage:set_string(player.."_rollback_storage", minetest.serialize(t))
	return e
end

local function refresh_rollback_storage(player)
	local t = minetest.deserialize(mod_storage:get_string(player.."_rollback_storage")) or {}
	mod_storage:set_string(player.."_rollback_storage", nil)
end

local function make_it_one(n)
	if n<0 then n=-1 end
	if n>0 then n=1 end
	return n
end

local function get_volume(pos1, pos2)
	if not pos1 or not pos2 then
		return 0
	end
	local lv = vector.subtract(pos1, pos2)
	return (math.abs(lv.x)+1) * (math.abs(lv.y)+1) * (math.abs(lv.z)+1)
end

local function get_pos_infotext(pos1, pos2)
	local lv = vector.subtract(pos1, pos2)
	lv.x = math.abs(lv.x)+1
	lv.y = math.abs(lv.y)+1
	lv.z = math.abs(lv.z)+1
	local it = lv.x.."x"..lv.y.."x"..lv.z
	local volume = lv.x*lv.y*lv.z
	if volume > max_volume then
		it = it.." = "..minetest.colorize("#ff0000", volume.." Blocks")
	else
		it = it.." = "..volume.." Blocks"
	end
	return it
end

local function check_owner(itemstack,name)
      local owner = itemstack:get_meta():get_string("owner")
		if not owner or owner == "" then
		      itemstack:get_meta():set_string("owner", name)	      
		end
		
		if owner ~= name then
		    minetest.chat_send_player(name, core.colorize("#ffbb00", ">>> This is not yours <<<"))
		    return false
		end
		
		return true
end

local function set_pos(itemstack, pos, player)
	local pos_name = minetest.pos_to_string(pos)
	local meta = itemstack:get_meta()
	local turner = meta:get_int("turner")
	local color = color_pos1
	local pos1 = minetest.string_to_pos(meta:get_string("pos1")) or {x=0,y=0,z=0}
	local pos2 = minetest.string_to_pos(meta:get_string("pos2")) or {x=0,y=0,z=0}
	if turner == 1 then
		pos2 = pos
		meta:set_string("pos2", pos_name)
		color = color_pos2
		turner = 0
	else
		pos1 = pos
		meta:set_string("pos1", pos_name)
		turner = 1
	end
	meta:set_int("turner", turner)
	minetest.chat_send_player(player:get_player_name(),
		"Filling Tool: "..minetest.colorize(color, "Pos")..
		" set to "..pos_name.." "..get_pos_infotext(pos1, pos2)
	)
	minetest.sound_play({name = sound_set_pos}, {pos = pos})
	local pos_under = table.copy(pos)
	pos_under.y = pos_under.y - 1
	if minetest.get_node(pos_under).name ~= "air" then
		minetest.add_particle({
			pos = pos,
			expirationtime = marker_time,
			vertical = true,
			size = 10,
			texture = "default_mese_post_light_side.png^[multiply:"..color,
			glow = 5
		})
	else
		minetest.add_particle({
			pos = pos,
			expirationtime = marker_time,
			size = 5,
			texture = "default_meselamp.png^[multiply:"..color,
			glow = 5
		})
	end
	return itemstack
end

local function get_next_pos(cpos, bpos, epos, dpos)
	if cpos.x ~= epos.x then
		cpos.x = cpos.x + dpos.x
	elseif cpos.z ~= epos.z then
		cpos.z = cpos.z + dpos.z
		cpos.x = bpos.x
	elseif cpos.y ~= epos.y then
		cpos.y = cpos.y + dpos.y
		cpos.x = bpos.x
		cpos.z = bpos.z
	else
		return false
	end
	return cpos
end

local function pos_can_place(pos, node_name, player)
	local node = minetest.get_node(pos).name
	if node == "ignore" then
		return false
	end
	local pnode = minetest.registered_nodes[node]
	local node_under = minetest.registered_nodes[minetest.get_node({x = pos.x, y = pos.y-1, z = pos.z}).name]
	if not pnode or not pnode.buildable_to then
		return false
	elseif node_under and minetest.get_item_group(node_name, "attached_node") > 0 and
			node_under.walkable == false then
		return false
	end
	return true
end

local function rollback_filling(player)
	local player_name = player:get_player_name()
	local inv = player:get_inventory()
	if player:get_attribute("filler_deactivate") == "true" then
		minetest.chat_send_player(player_name, "Filling Tool: Deactivated.")
		player:set_attribute("filler_deactivate", "false")
		player:set_attribute("filler_activated", "false")
		return
	end
	local rollback_storage = get_rollback_storage(player_name)
	if not rollback_storage or rollback_storage == {} then
		player:set_attribute("filler_activated", "false")
		return
	end
	local node = minetest.get_node(rollback_storage.pos)
	while node.name ~= rollback_storage.node.name do
		rollback_storage = get_rollback_storage(player_name)
		if not rollback_storage or rollback_storage == {} then
			player:set_attribute("filler_activated", "false")
			return
		end
		node = minetest.get_node(rollback_storage.pos)
	end
	minetest.set_node(rollback_storage.pos, {name="air"})                  -- this more save in case of clay and other things which change shape if dug
	if inv:room_for_item("main", node.name) then
		inv:add_item("main", node.name)                                        -- in case of rollback, dug items should be returned
	else
		minetest.item_drop(ItemStack(node.name), player, rollback_storage.pos)
	end
	local node_sounds = minetest.registered_nodes[node.name].sounds
	if node_sounds and node_sounds.dug then
		minetest.sound_play(minetest.registered_nodes[node.name].sounds.dug, {pos = rollback_storage.pos})
	else
		--minetest.sound_play("", {pos = rollback_storage.pos})
	end
	minetest.after(speed, rollback_filling, player)
end

local function fill_area(cpos, bpos, epos, node, player, dpos, inv) --cpos, dpos and inv to improve performance
	local player_name = player:get_player_name()
	if player:get_attribute("filler_deactivate") == "true" then
		minetest.chat_send_player(player_name, "Filling Tool: Deactivated.")
		player:set_attribute("filler_deactivate", "false")
		player:set_attribute("filler_activated", "false")
		return
	end
	while not pos_can_place(cpos, node.name) do
		cpos = get_next_pos(cpos, bpos, epos, dpos)
		if not cpos then
			player:set_attribute("filler_activated", "false")
			return
		end -- finished
	end
	-- check if protected discrete
	if minetest.is_protected(cpos, player_name) then
		minetest.chat_send_player(player_name,
			"Filling Tool:"..minetest.colorize("#ff0000", " Stop! ")..
			"This area is protected!")
		minetest.sound_play({name = sound_placing_failed}, {pos = cpos})
		player:set_attribute("filler_activated", "false")
		return
	end
	if not inv:contains_item("main", node.name) and not filler.endless_placeable[node.name] and
			not minetest.setting_getbool("creative_mode") then
		minetest.chat_send_player(player_name,
			"Filling Tool:"..minetest.colorize("#ff0000", " Stop! ").."You are out of "..
			'"'..minetest.registered_nodes[node.name].description..'"!')
		minetest.sound_play({name = sound_placing_failed}, {pos = cpos})
		player:set_attribute("filler_activated", "false")
		return
	end
	
	-- place node
	if not filler.endless_placeable[node.name] and not minetest.setting_getbool("creative_mode") then
		inv:remove_item("main", node.name)
	end

	-- works perfect but bad performance
	minetest.item_place_node(ItemStack(node.name), player, {type="node", under=cpos, above=cpos}, node.param2)
	
	-- alternatives
	--minetest.add_node(cpos, node)
	--minetest.place_node(cpos, node)
	
	add_rollback_storage(player_name, cpos, node)
	local node_sounds = minetest.registered_nodes[node.name].sounds
	if node_sounds and node_sounds.place then
		minetest.sound_play(minetest.registered_nodes[node.name].sounds.place, {pos = cpos})
	else
		--minetest.sound_play("", {pos = cpos})
	end
	
	cpos = get_next_pos(cpos, bpos, epos, dpos)
	if not cpos then
		player:set_attribute("filler_activated", "false")
		return
	end -- finished
	minetest.after(speed, fill_area, cpos, bpos, epos, node, player, dpos, inv)
end

minetest.register_tool("filler:filler", {
	description = "Filling Tool",
	inventory_image = "filler_filler.png",
	on_place = function(itemstack, placer, pointed_thing)
		if not pointed_thing.type == "node" then
			return itemstack
		end
		if placer:get_player_control().sneak == true then
			local node = minetest.get_node(pointed_thing.under)
			if not minetest.registered_nodes[node.name] then
				return itemstack
			end
			itemstack:get_meta():set_string("node", minetest.serialize(node))
			minetest.chat_send_player(placer:get_player_name(),
				"Filling Tool: Node set to "..
				'"'..minetest.registered_nodes[node.name].description..'"')
			minetest.sound_play({name = sound_scan_node}, {pos = pointed_thing.under})
		else
			return set_pos(itemstack, pointed_thing.above, placer)
		end
		return itemstack
	end,
	on_secondary_use = function(itemstack, user)
		local pos = vector.round(user:get_pos())
		if user:get_player_control().sneak == true then
			local node = minetest.get_node(pos)
			if not minetest.registered_nodes[node.name] then
				return itemstack
			end
			itemstack:get_meta():set_string("node", minetest.serialize(node))
			minetest.chat_send_player(user:get_player_name(),
				"Filling Tool: Node set to "..
				'"'..minetest.registered_nodes[node.name].description..'"')
			minetest.sound_play({name = sound_scan_node}, {pos = pos})
		else
			return set_pos(itemstack, pos, user)
		end
		return itemstack
	end,
	on_use = function(itemstack, user, pointed_thing)
		local player_name = user:get_player_name()
		if user:get_attribute("filler_activated") == "true" then
			minetest.chat_send_player(player_name, "Filling Tool: The filling tool is currently working."..
				" (You can hold sneak and left click to deactivate it.)")
			if user:get_player_control().sneak == true then
				user:set_attribute("filler_deactivate", "true")
			end
			return
		end
		local meta = itemstack:get_meta()
		local pos1 = minetest.string_to_pos(meta:get_string("pos1"))
		local pos2 = minetest.string_to_pos(meta:get_string("pos2"))
		local node = minetest.deserialize(meta:get_string("node"))
		local volume = get_volume(pos1, pos2)
		if not user then return end
		local inv = user:get_inventory()
		
		-- Ownercheck added here.
		if ownercheck and not check_owner(itemstack,player_name) then
		    return itemstack
		end
		-- End Ownercheck
		
		if not node then
			minetest.chat_send_player(player_name, "Filling Tool: Hold sneak and right click to select a node.")
			return
		end
		if not pos1 or not pos2 then
			minetest.chat_send_player(player_name, "Filling Tool: Right click to set coordinates.")
			return
		end
		if volume > max_volume then
			minetest.chat_send_player(player_name, "Filling Tool: This area is too big.")
			return
		end
		if filler.blacklist[node.name] == true then
			minetest.chat_send_player(player_name, 'Filling Tool: "'..
				minetest.registered_nodes[node.name].description..'"'.." can't be placed with the filling tool.")
			return
		end
		local bpos = table.copy(pos1)
		local epos = table.copy(pos2)
		local cdpos = 1
		if filler.placing_from_top_to_bottom[node.name] == true then
			cdpos = -1
			if pos1.y < pos2.y then
				bpos = table.copy(pos2)
				epos = table.copy(pos1)
			end
		else
			if pos1.y > pos2.y then
			bpos = table.copy(pos2)
			epos = table.copy(pos1)
		end
		end
		local cpos = table.copy(bpos)
		local dpos = vector.direction(bpos, epos)
		dpos.x = make_it_one(dpos.x)
		dpos.y = cdpos
		dpos.z = make_it_one(dpos.z)
		refresh_rollback_storage(player_name)
		user:set_attribute("filler_activated", "true")
		fill_area(cpos, bpos, epos, node, user, dpos, inv)
	end,
})

minetest.register_chatcommand("rsq", {
	description = "Revert the last filling action",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if player:get_attribute("filler_activated") == "true" then
			minetest.chat_send_player(name, "Filling Tool: The filling tool is currently working."..
				" (You can hold sneak and left click to deactivate it.)")
			return
		end
		player:set_attribute("filler_activated", "true")
		rollback_filling(player)
	end
})

minetest.register_on_joinplayer(function(player)
	player:set_attribute("filler_activated", "false")
end)

if recipe_on then                         -- this tool is a bit dangerous on multiplayer servers
	  minetest.register_craft({
		  output = 'filler:filler',
		  recipe = {
			  {'', 'default:mese_post_light', 'default:diamond'},
			  {'', 'default:steel_ingot', 'default:mese_post_light'},
			  {'group:stick', '', ''},
		  }
	  })
end
