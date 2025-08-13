from valvebsp import Bsp
from valvebsp.lumps import LUMP_ENTITIES
from pprint import pprint

import argparse
import pyparsing as pp
import logging
import lzma
import re
import struct

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s:%(lineno)s: %(message)s"
)
logger = logging.getLogger(__name__)

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

# FIXME: ugly fix
BLACKLIST_MATH_COUNTERS = [
    "pirate_counter", # ze_doom3_v1
]

def tryint(x, fallback=False):
    try:
        return round(float(x))
    except ValueError:
        pass

    if fallback:
        return x
    else:
        return 0

def get_logic_eventname(logic_entity):
    if logic_entity.classname == "logic_compare":
        return "OnEqualTo"
    if logic_entity.classname == "logic_branch":
        return "OnTrue"
    return "OnTrigger"

class EventParams:
    def __init__(self, line):
        self.targetname, self.targetinput, self.parameter, self.delay, self.refire = re.split(r"\s*,\s*", line)

    def __repr__(self):
        return f"EventParams(targetname=\"{self.targetname}\", targetinput=\"{self.targetinput}\", parameter=\"{self.parameter}\", delay=\"{self.delay}\", refire=\"{self.refire}\")"

class Entity:
    def __init__(self, entity_info):
        self.hammerid = 0
        self.classname = "None"
        self.parentname = "None"
        self.targetname = "None"
        self.filtername = "None"
        self.templates = []
        self.events = {}
        self.raw = {}

        for vals in entity_info:
            x, y = vals[0], vals[1]
            if x == "id" or x == "hammerid":
                self.hammerid = tryint(y)
            elif x == "classname":
                self.classname = y
            elif x == "parentname":
                self.parentname = y
            elif x == "targetname":
                self.targetname = y
            elif x == "filtername":
                self.filtername = y
            elif x[:8] == "Template":
                self.templates.append(y)
            elif x[:2] == "On" and x[2].isupper():
                self.events.setdefault(x, [])
                self.events[x].append(EventParams(y))
            else:
                self.raw.setdefault(x, y)

    def __repr__(self):
        return f"Entity(hammerid={self.hammerid}, classname=\"{self.classname}\", parentname=\"{self.parentname}\", targetname=\"{self.targetname}\", filtername=\"{self.filtername}\", templates={self.templates}, events={self.events}, raw={self.raw})"

    def get_events(self, name):
        return self.events.get(name, [])

class ParseBSP:
    def __init__(self, source_path):
        self.bsp = Bsp(source_path)
        self.lump_header = self.bsp._get_lump_header(LUMP_ENTITIES)

        with open(self.bsp.source_path, "rb") as file:
            file.seek(self.lump_header.fileofs)
            self.lump_raw = file.read(self.lump_header.filelen)

        self.entity_list = []
        self.entity_list_by_names = {}
        self.entity_list_by_classes = {}
        self.entity_list_by_parentname = {}

    def parse(self):
        if self.lump_raw[:4] == b'LZMA':
            header, actual_size, lzma_size, properties = struct.unpack_from("<III 5s", self.lump_raw)
            self.lump_raw = struct.pack("<5s Q", properties, actual_size) + self.lump_raw[17:]
            self.lump_raw = lzma.decompress(self.lump_raw)

        # avoid decoding errors
        lump_raw = self.lump_raw.decode("ascii", errors="ignore")
        with open("test.lzma", "wb") as file:
            file.write(self.lump_raw)
        lump_raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", lump_raw)

        # parse all entities
        entity_property_encoding = pp.Group(pp.QuotedString('"', multiline=True) * 2)
        entity_encoding = pp.nested_expr("{", "}", entity_property_encoding, None)
        lump_0_encoding = pp.ZeroOrMore(entity_encoding)
        entity_list_raw = lump_0_encoding.parse_string(lump_raw, parse_all=True)

        # convert raw lists to dict
        for entity_raw in entity_list_raw:
            self.entity_list.append(Entity(entity_raw))

        # sort all by name and classname
        for entity in self.entity_list:
            if entity.targetname is not None:
                self.entity_list_by_names.setdefault(entity.targetname, entity)
            if entity.classname is not None:
                self.entity_list_by_classes.setdefault(entity.classname, [])
                self.entity_list_by_classes[entity.classname].append(entity)
            if entity.parentname is not None:
                self.entity_list_by_parentname.setdefault(entity.parentname, [])
                self.entity_list_by_parentname[entity.parentname].append(entity)

    def get_entity_by_targetname(self, targetname):
        return self.entity_list_by_names.get(targetname)

    def get_entities_by_classname(self, classname):
        return self.entity_list_by_classes.get(classname, [])
    
    def get_entities_by_parentname(self, parentname):
        return self.entity_list_by_parentname.get(parentname, [])

    def find_point_template_by_weaponname(self, weaponname):
        for point_template in self.get_entities_by_classname("point_template"):
            if weaponname in point_template.templates:
                return point_template

    def find_filter_name_by_func_button(self, func_button):
        filter_name = None
        for params in func_button.get_events("OnPressed"):
            entity = self.get_entity_by_targetname(params.targetname)
            if entity is not None and entity.classname == "filter_activator_name":
                filter_name = entity
                break
        return filter_name

    def find_entities_by_filter_name(self, filter_name):
        logic_entity, trigger_entity, math_counter = None, None, None

        for params in filter_name.get_events("OnPass"):
            entity = self.get_entity_by_targetname(params.targetname)
            if not entity:
                continue

            if not logic_entity and entity.classname[:6] == "logic_":
                logic_entity = entity
                continue
            if not trigger_entity and entity.classname[:8] == "trigger_":
                trigger_entity = entity
                continue
            if not math_counter and entity.classname == "math_counter":
                math_counter = entity
                continue

        return logic_entity, trigger_entity, math_counter

    def find_entities_by_logic_entity(self, logic_entity):
        trigger_entity, math_counter = None, None

        for params in logic_entity.get_events(get_logic_eventname(logic_entity)):
            entity = self.get_entity_by_targetname(params.targetname)
            if not entity:
                continue

            if not trigger_entity and entity.classname[:8] == "trigger_":
                trigger_entity = entity
                continue
            if not math_counter and entity.classname == "math_counter":
                math_counter = entity
                continue

        return trigger_entity, math_counter

    def find_all_by_point_template(self, point_template):
        func_button, filter_name, logic_entity, trigger_entity, math_counter = None, None, None, None, None

        for entname in point_template.templates:
            entity = self.get_entity_by_targetname(entname)
            if entity is None:
                continue

            if entity.classname in ["func_button", "func_rot_button", "func_physbox_multiplayer", "func_door", "func_door_rotating", "game_ui"]:
                func_button = entity
                continue
            if entity.classname == "filter_activator_name":
                filter_name = entity
                continue
            if entity.classname[:6] == "logic_":
                logic_entity = entity
                continue
            if entity.classname[:8] == "trigger_":
                trigger_entity = entity
                continue
            if entity.classname == "math_counter":
                math_counter = entity
                continue

        if not filter_name and func_button:
            filter_name = self.find_filter_name_by_func_button(func_button)

        if filter_name and not logic_entity:
            logic_entity, trigger_entity, math_counter = self.find_entities_by_filter_name(filter_name)

        #if logic_entity and not math_counter:
        #    trigger_entity, math_counter = self.find_entities_by_logic_entity(logic_entity)

        return func_button, filter_name, logic_entity, trigger_entity, math_counter

    def find_all_by_parentname(self, weapon):
        func_button, filter_name, logic_entity, trigger_entity, math_counter = None, None, None, None, None

        parentname = weapon.targetname

        for params in weapon.get_events("OnPlayerPickup"):
            entity = self.get_entity_by_targetname(params.targetname)
            if entity and entity.classname in ["func_button", "func_rot_button", "func_door", "func_door_rotating", "game_ui"] and entity.parentname == parentname:
                func_button = entity
                break

        if not func_button:
            for entity in self.get_entities_by_parentname(parentname):
                if entity.classname in ["func_button", "func_rot_button", "func_door", "func_door_rotating", "game_ui"]:
                    func_button = entity
                    break

        if func_button is None:
            return func_button, filter_name, logic_entity, trigger_entity, math_counter

        if not filter_name:
            filter_name = self.find_filter_name_by_func_button(func_button)

        if filter_name:
            logic_entity, trigger_entity, math_counter = self.find_entities_by_filter_name(filter_name)

        if logic_entity:
            trigger_entity, math_counter = self.find_entities_by_logic_entity(logic_entity)

        return func_button, filter_name, logic_entity, trigger_entity, math_counter

    def get_config_raw(self, config, weapon, func_button=None, filter_name=None, logic_entity=None, trigger_entity=None, math_counter=None):
        if not func_button:
            logger.info("%s: mode = ENTWATCH_MODE_NOBUTTON", config["name"])
            config["mode"] = 0
            return config

        for params in weapon.get_events("OnPlayerPickup"):
            if params.targetname == "!activator" and params.targetinput == "AddOutput" and params.parameter[:11] == "targetname ":
                config["filtername"] = params.parameter[11:]
                logger.info("%s: filtername = \"%s\"", config["name"], config["filtername"])

        if filter_name and not config.get("filtername"):
            config["filtername"] = filter_name.filtername
            logger.info("%s: filtername = \"%s\"", config["name"], config["filtername"])

        config["buttonclass"] = func_button.classname
        config["buttonid"] = func_button.hammerid
        config["buttonname"] = func_button.targetname

        logger.info("%s: found \"%s\" with hammerid = %i and targetname = \"%s\"", config["name"], config["buttonclass"], config["buttonid"], config["buttonname"])

        if math_counter and tryint(math_counter.raw.get("max", 0)) > 2000:
            math_counter = None
        elif math_counter and tryint(math_counter.raw.get("min", 0)) == 0 and tryint(math_counter.raw.get("max", 0)) == 0 and tryint(math_counter.raw.get("startvalue", 0)) == 0:
            math_counter = None

        if math_counter and math_counter.targetname not in BLACKLIST_MATH_COUNTERS:
            config["energyid"] = math_counter.hammerid
            config["energyname"] = math_counter.targetname

        if trigger_entity:
            config["triggerid"] = trigger_entity.hammerid
            config["triggername"] = trigger_entity.targetname

        config["mode"] = 0

        for params in func_button.get_events("OnPressed"):
            if params.targetname == config.get("buttonname"):
                if params.targetname == config.get("buttonname"):
                    if params.targetinput == "Unlock" and config.get("cooldown", 0) == 0:
                        config["cooldown"] = tryint(params.delay)
                        logger.info("%s: cooldown = %i", config["name"], config["cooldown"])

        if filter_name or logic_entity:
            lock, unlock, kill = False, False, False

            for events in [filter_name and filter_name.get_events("OnPass") or [], logic_entity and logic_entity.get_events(get_logic_eventname(logic_entity)) or []]:
                for params in events:
                    if params.targetname == config.get("buttonname"):
                        if params.targetinput == "Lock":
                            lock = True
                        if params.targetinput == "Unlock" and config.get("cooldown", 0) == 0:
                            unlock = True
                            config["cooldown"] = tryint(params.delay)
                            logger.info("%s: cooldown = %i", config["name"], config["cooldown"])
                        if params.targetinput == "Kill":
                            kill = True

                    if params.targetname == config.get("triggername"):
                        if params.targetinput == "Enable" and config.get("cooldown", 0) == 0:
                            config["cooldown"] = tryint(params.delay)
                            logger.info("%s: cooldown = %i", config["name"], config["cooldown"])

            if lock and not unlock or kill:
                logger.info("%s: mode = ENTWATCH_MODE_LIMITED_USES", config["name"])
                config["mode"] = 3
                return config

        if math_counter and math_counter.targetname not in BLACKLIST_MATH_COUNTERS:
            if math_counter.raw.get("startvalue") is not None:
                config["currentvalue"] = tryint(math_counter.raw.get("startvalue"), fallback=True)
            if math_counter.raw.get("min") is not None:
                config["hitmin"] = tryint(math_counter.raw.get("min"), fallback=True)
            if math_counter.raw.get("max") is not None:
                config["hitmax"] = tryint(math_counter.raw.get("max"), fallback=True)

            if len(math_counter.get_events("OnHitMin")) > 0:
                logger.info("%s: mode = ENTWATCH_MODE_COUNTER_FMIN_REACHED", config["name"])
                config["mode"] = 4

                for params in math_counter.get_events("OnHitMin"):
                    if params.targetname == config.get("buttonname"):
                        if params.targetinput == "Unlock" and config.get("cooldown", 0) == 0:
                            config["cooldown"] = tryint(params.delay)
                            logger.info("%s: cooldown = %i", config["name"], config["cooldown"])
            elif len(math_counter.get_events("OnHitMax")) > 0:
                logger.info("%s: mode = ENTWATCH_MODE_COUNTER_FMAX_REACHED", config["name"])
                config["mode"] = 5

                for params in math_counter.get_events("OnHitMax"):
                    if params.targetname == config.get("buttonname"):
                        if params.targetinput == "Unlock" and config.get("cooldown", 0) == 0:
                            config["cooldown"] = tryint(params.delay)
                            logger.info("%s: cooldown = %i", config["name"], config["cooldown"])
            else:
                logger.error(f"%s: math_counter found, but mode is not valid", config["name"])

            return config

        logger.info("%s: mode = ENTWATCH_MODE_COOLDOWNS", config["name"])
        config["mode"] = 2
        return config

def main(source_path):
    logger.debug("source_path = %s", source_path)
    logger.info("parsing BSP file")
    bsp = ParseBSP(source_path)
    bsp.parse()

    logger.info("parsing done, now trying to get config for all weapons")
    entwatch_config_list = []

    for weapon_class in CSS_WEAPONS:
        for weapon in bsp.get_entities_by_classname(weapon_class):
            config = {}
            config["name"] = weapon.targetname
            config["shortname"] = config["name"]
            config["filtername"] = ""
            config["hammerid"] = weapon.hammerid

            logger.info("%s: hammerid = %i", config["name"], config["hammerid"])

            point_template = bsp.find_point_template_by_weaponname(weapon.targetname)
            if not point_template:
                func_button, filter_name, logic_entity, trigger_entity, math_counter = bsp.find_all_by_parentname(weapon)
            else:
                func_button, filter_name, logic_entity, trigger_entity, math_counter = bsp.find_all_by_point_template(point_template)

            logger.debug("%s: func_button = %s", config["name"], func_button)
            logger.debug("%s: filter_activator_name = %s", config["name"], filter_name)
            logger.debug("%s: logic_entity = %s", config["name"], logic_entity)
            logger.debug("%s: trigger_entity = %s", config["name"], trigger_entity)
            logger.debug("%s: math_counter = %s", config["name"], math_counter)

            config = bsp.get_config_raw(config, weapon, func_button, filter_name, logic_entity, trigger_entity, math_counter)

            if point_template:
                config["pt_spawner"] = point_template.targetname

            logger.debug("%s: %s", config["name"], config)

            entwatch_config_list.append(config)
            logger.debug("%s: done", config["name"])

    return entwatch_config_list

def fix_config(config):
    def save_remove(c, k):
        try:
            c.pop(k, None)
        except KeyError:
            pass

    logger.debug("Cleanup config from garbage")

    for cfg in config:
        save_remove(cfg, "buttonclass")
        save_remove(cfg, "buttonname")
        save_remove(cfg, "energyid")
        save_remove(cfg, "triggerid")
        save_remove(cfg, "triggername")

        if len(cfg.get("filtername", "")) == 0:
            save_remove(cfg, "filtername")
        if cfg.get("cooldown", 0) < 2:
            save_remove(cfg, "cooldown")

        if cfg["mode"] == 1:
            cfg["mode"] = "ENTWATCH_MODE_SPAM_PROTECTION_ONLY"
        elif cfg["mode"] == 2:
            cfg["mode"] = "ENTWATCH_MODE_COOLDOWNS"
        elif cfg["mode"] == 3:
            cfg["mode"] = "ENTWATCH_MODE_LIMITED_USES"
        elif cfg["mode"] == 4:
            cfg["mode"] = "ENTWATCH_MODE_COUNTER_FMIN_REACHED"
        elif cfg["mode"] == 5:
            cfg["mode"] = "ENTWATCH_MODE_COUNTER_FMAX_REACHED"
        else:
            cfg["mode"] = "ENTWATCH_MODE_NOBUTTON"
            save_remove(cfg, "filtername")

    return config

def save_config(config, out_config, hard_tab=False):
    def format_one_config(cfg):
        l = []
        for key, value in cfg.items():
            if isinstance(value, str):
                if value[:8] != "ENTWATCH":
                    value = "\"" + value + "\""
            l.append(f"[\"{key}\"] = {value},")
        return "\t{\n\t\t" + "\n\t\t".join(l) + "\n\t},\n"

    with open(out_config, "w") as file:
        file.write("return {\n")
        for cfg in config:
            text = format_one_config(cfg)
            if not hard_tab:
                text = text.replace("\t", 4 * " ")
            file.write(text)
        file.write("}")

    logger.info("Config was saved to %s", out_config)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("source_path", help="BSP file")
    parser.add_argument("out_config", help="Output config file")
    parser.add_argument("-t", "--hard-tab", action="store_true", help="Save config file with hard tabs")
    parser.add_argument("-c", "--no-clear-config", action="store_true", help="Do not clear config with useless variables")
    args = parser.parse_args()

    config = main(args.source_path)
    if not args.no_clear_config:
        config = fix_config(config)
    save_config(config, args.out_config, hard_tab = args.hard_tab)