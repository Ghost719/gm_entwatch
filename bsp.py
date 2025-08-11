from valvebsp import Bsp
from valvebsp.lumps import LUMP_ENTITIES
from pprint import pprint

import argparse
import pyparsing as pp
import re

entity_list_by_names = {}
entity_list_by_classes = {}
entity_list_by_parentname = {}

CSS_WEAPONS = [
    "weapon_knife",
    "weapon_glock",
    "weapon_usp",
    "weapon_p228",
    "weapon_deagle",
    "weapon_elite",
    "weapon_fiveseven",
    "weapon_m3",
    "weapon_xm1014",
    "weapon_galil",
    "weapon_ak47",
    "weapon_scout",
    "weapon_sg552",
    "weapon_awp",
    "weapon_g3sg1",
    "weapon_famas",
    "weapon_m4a1",
    "weapon_aug",
    "weapon_sg550",
    "weapon_mac10",
    "weapon_tmp",
    "weapon_mp5navy",
    "weapon_ump45",
    "weapon_p90",
    "weapon_m249",
]

def parse_event_params(line):
    targetname, targetinput, parameter, delay, refire = re.split(r"\s*,\s*", line)
    return targetname, targetinput, parameter, delay, refire

def find_point_template_by_weapon(entlist, weapon):
    for entity in entlist:
        if entity.get("__Templates") is None:
            continue
        if weapon.get("targetname") in entity.get("__Templates"):
            return entity

def find_all_entities_by_point_template(point_template):
    func_button, filter_name, logic_entity, trigger_hurt, math_counter = None, None, None, None, None

    for entname in point_template.get("__Templates", []):
        entity = entity_list_by_names.get(entname)
        if entity is None:
            continue

        classname = entity.get("classname")
        if classname in ["func_button", "func_rot_button", "func_physbox_multiplayer", "func_door", "func_door_rotating", "game_ui"]:
            func_button = entity
            continue
        if classname == "filter_activator_name":
            filter_name = entity
            continue
        if classname == "logic_relay":
            logic_entity = entity
            continue
        if classname == "trigger_hurt":
            trigger_hurt = entity
            continue
        if classname == "math_counter":
            math_counter = entity
            continue

    return func_button, filter_name, logic_entity, trigger_hurt, math_counter

def find_all_entities_by_parentname(parentname):
    func_button, filter_name, logic_entity, trigger_hurt, math_counter = None, None, None, None, None

    for entity in entity_list_by_parentname.get(parentname, []):
        classname = entity.get("classname")
        if classname in ["func_button", "func_rot_button", "func_physbox_multiplayer", "func_door", "func_door_rotating", "game_ui"]:
            func_button = entity
            continue
        if classname == "filter_activator_name":
            filter_name = entity
            continue
        if classname[:6] == "logic_":
            logic_entity = entity
            continue
        if classname == "trigger_hurt":
            trigger_hurt = entity
            continue
        if classname == "math_counter":
            math_counter = entity
            continue

    if func_button is None:
        return func_button, filter_name, logic_entity, trigger_hurt, math_counter

    if filter_name is None:
        for x in func_button.get("OnPressed", []):
            targetname, targetinput, parameter, delay, refire = parse_event_params(x)
            entity = entity_list_by_names.get(targetname)
            if entity is not None and entity.get("classname") == "filter_activator_name":
                filter_name = entity
                break

    if filter_name is not None and logic_entity is None:
        for x in filter_name.get("OnPass", []):
            targetname, targetinput, parameter, delay, refire = parse_event_params(x)
            entity = entity_list_by_names.get(targetname)
            if entity is not None and entity.get("classname")[:6] == "logic_":
                logic_entity = entity
                break

    return func_button, filter_name, logic_entity, trigger_hurt, math_counter

def get_config_raw(config, entity_list_by_names, func_button = None, filter_name = None, logic_entity = None, trigger_hurt = None, math_counter = None):
    if func_button is not None:
        config["buttonclass"] = func_button.get("classname")
        config["buttonid"] = func_button.get("hammerid")
        config["buttonname"] = func_button.get("targetname")

        print(f"INFO: {config['name']}: found {config['buttonclass']} with hammerid = {config['buttonid']} and targetname = {config['buttonname']}")

        for x in func_button.get("OnPlayerPickup", []):
            targetname, targetinput, parameter, delay, refire = parse_event_params(x)
            if targetname == "!activator" and targetinput == "AddOutput" and parameter[:11] == "targetname ":
                config["filtername"] = parameter[11:]
                print(f"INFO: {config['name']}: found filtername = {config['filtername']}")
                break
    else:
        print(f"ERROR: {config['name']}: button not found")

    if filter_name is not None:
        if len(config.get("filtername", "")) == 0 and filter_name.get("filtername") is not None:
            config["filtername"] = filter_name.get("filtername")
            print(f"INFO: {config['name']}: found filtername = {config['filtername']}")
        elif len(config.get("filtername", "")) > 0 and filter_name.get("filtername") is not None and filter_name.get("filtername") != config["filtername"]:
            config["filtername"] = filter_name.get("filtername")
            print(f"WARN: {config['name']}: override filtername with {config['filtername']}")

        if math_counter is None:
            for x in filter_name.get("OnPass", []):
                targetname, targetinput, parameter, delay, refire = parse_event_params(x)
                if targetinput in ["Enable", "Disable", "Add", "Subtract", "Divide", "Multiply", "SetValue", "SetValueNoFire", "SetHitMax", "SetHitMin"]:
                    mc = entity_list_by_names.get(targetname)
                    if mc is not None:
                        print(f"INFO: {config['name']}: found math_counter in filter_activator_name")
                        math_counter = mc
    else:
        print(f"ERROR: {config['name']}: filter_activator_name not found")

    if trigger_hurt is not None:
        config["triggerid"] = trigger_hurt.get("hammerid")
        config["triggername"] = trigger_hurt.get("targetname")
    else:
        print(f"ERROR: {config['name']}: trigger_hurt not found")

    if logic_entity is not None:
        lockfound = False
        unlockfound = False

        if logic_entity.get("classname") == "logic_relay":
            for x in logic_entity.get("OnTrigger", []):
                targetname, targetinput, parameter, delay, refire = parse_event_params(x)
                if targetname == config["buttonname"] and targetinput == "Lock":
                    lockfound = True
                if targetname == config["buttonname"] and targetinput == "Unlock":
                    unlockfound = True
                    if config.get("cooldown", 0) == 0:
                        config["cooldown"] = int(delay)
                        print(f"INFO: {config['name']}: found cooldown = {config['cooldown']}")
                if math_counter is None and targetinput in ["Enable", "Disable", "Add", "Subtract", "Divide", "Multiply", "SetValue", "SetValueNoFire", "SetHitMax", "SetHitMin"]:
                    mc = entity_list_by_names.get(targetname)
                    if mc is not None:
                        print(f"INFO: {config['name']}: found math_counter in logic_relay")
                        math_counter = mc
                if trigger_hurt is not None and targetname == config.get("triggername") and targetinput == "Enable":
                    if config.get("cooldown", 0) == 0:
                        config["cooldown"] = int(delay)
                        print(f"INFO: {config['name']}: found cooldown = {config['cooldown']}")

        if lockfound and not unlockfound:
            config["mode"] = 3
            print(f"INFO: {config['name']}: mode = ENTWATCH_MODE_LIMITED_USES")

        if config.get("mode", 0) == 0:
            if math_counter is not None:
                if math_counter.get("startvalue") is not None:
                    config["currentvalue"] = math_counter.get("startvalue")
                if math_counter.get("min") is not None:
                    config["hitmin"] = math_counter.get("min")
                if math_counter.get("max") is not None:
                    config["hitmax"] = math_counter.get("max")

                if math_counter.get("OnHitMin") is not None:
                    config["mode"] = 4
                    print(f"INFO: {config['name']}: mode = ENTWATCH_MODE_COUNTER_FMIN_REACHED")
                elif math_counter.get("OnHitMax") is not None:
                    config["mode"] = 5
                    print(f"INFO: {config['name']}: mode = ENTWATCH_MODE_COUNTER_FMAX_REACHED")
                else:
                    print(f"ERROR: {config['name']}: math_counter found, but mode is not valid")
            else:
                print(f"ERROR: {config['name']}: math_counter not found")
                config["mode"] = 2
    else:
        print(f"ERROR: {config['name']}: logic_relay not found")

    return config

def main(source_path):
    print(f"INFO: source_path = {source_path}")
    bsp = Bsp(source_path)
    lump_header = bsp._get_lump_header(LUMP_ENTITIES)

    with open(bsp.source_path, "rb") as file:
        file.seek(lump_header.fileofs)
        lump_raw = file.read(lump_header.filelen)

    # avoid decoding errors
    print("INFO: parsing BSP")
    lump_raw = lump_raw.decode("ascii", errors="ignore")
    lump_raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", lump_raw)

    # parse all entities
    entity_property_encoding = pp.Group(pp.QuotedString('"', multiline=True) * 2)
    entity_encoding = pp.nested_expr("{", "}", entity_property_encoding, None)
    lump_0_encoding = pp.ZeroOrMore(entity_encoding)
    entity_list_raw = lump_0_encoding.parse_string(lump_raw, parse_all=True)

    # convert raw lists to dict
    entity_list = []
    for entity in entity_list_raw:
        info = {}
        for vals in entity:
            x, y = vals[0], vals[1]
            if x[:2] == "On":
                info.setdefault(x, [])
                info[x].append(y)
            elif x[:8] == "Template":
                info.setdefault("__Templates", [])
                info["__Templates"].append(y)
            else:
                info.setdefault(x, y)
        entity_list.append(info)

    # sort all by name and classname
    for entity in entity_list:
        if entity.get("targetname") is not None:
            entity_list_by_names.setdefault(entity.get("targetname"), entity)
        if entity.get("classname") is not None:
            entity_list_by_classes.setdefault(entity.get("classname"), [])
            entity_list_by_classes[entity.get("classname")].append(entity)
        if entity.get("parentname") is not None:
            entity_list_by_parentname.setdefault(entity.get("parentname"), [])
            entity_list_by_parentname[entity.get("parentname")].append(entity)

    print("INFO: parsing done, now trying to get config for all weapons")

    entwatch_config_list = []

    for weapon_class in CSS_WEAPONS:
        weapon_list = entity_list_by_classes.get(weapon_class)
        if weapon_list is None:
            continue

        for weapon in weapon_list:
            config = {}
            config["name"] = weapon.get("targetname")
            config["shortname"] = config["name"]
            config["hammerid"] = weapon.get("hammerid")

            print(f"INFO: {config['name']}: hammerid = {config['hammerid']}")

            point_template = find_point_template_by_weapon(entity_list_by_classes.get("point_template", {}), weapon)
            if point_template is None:
                func_button, filter_name, logic_relay, trigger_hurt, math_counter = find_all_entities_by_parentname(config["name"])
            else:
                func_button, filter_name, logic_relay, trigger_hurt, math_counter = find_all_entities_by_point_template(point_template)

            config = get_config_raw(config, entity_list_by_names, func_button = func_button, filter_name = filter_name, logic_relay = logic_relay, trigger_hurt = trigger_hurt, math_counter = math_counter)

            entwatch_config_list.append(config)
            print(f"INFO: {config['name']}: done")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("source_path", help="BSP file")
    args = parser.parse_args()

    main(args.source_path)