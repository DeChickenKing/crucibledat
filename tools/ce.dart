/*
 * Copyright 2019 Mike Chambers, Grant Skinner
 * Released under an MIT License
 * https://opensource.org/licenses/MIT
 */

import 'dart:convert';
import 'dart:io' hide Platform;

import "../lib/platform.dart";

import "../lib/d2api.dart";
import "../lib/member_info_result.dart";
import "../lib/character.dart";
import "../lib/game_report.dart";
import "../lib/class_type.dart";
import "../lib/experience_type.dart";

import 'package:args/args.dart';

D2Api d2api;
String _seperator = ",";
String _lineSeperator = "\n";
String _outputPath = "activity_history";
int _downloadBatchCount = 5;


void main(List<String> args) async {

  ArgParser parser = ArgParser();

  parser.addOption("apikey", abbr: "a");
  parser.addOption("platform", abbr: "p");
  parser.addOption("gamertag", abbr: "t");
  parser.addOption("output", abbr: "o");
  parser.addFlag("verbose"); //where to print extra info
  parser.addFlag("hunter"); //retrieve stats for hunter
  parser.addFlag("titan"); //retrieve stats for titan
  parser.addFlag("warlock"); //retrieve stats for warlock
  parser.addFlag("help"); //retrieve stats for warlock
  parser.addFlag("csv");
  parser.addFlag("json");

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch(e) {
    printUsage();
    exit(2);
  }

  if(results["help"]) {
    printUsage();
    exit(1);
  }

  String apikey = results["apikey"];
  String platformLabel = results["platform"];
  String gamertag = results["gamertag"];

  if (apikey == null || platformLabel == null || gamertag == null) {
    printUsage();
    exit(2);
  }

  int platformId = Platform.fromLabel(platformLabel);

  if(platformId == null) {
    printUsage();
    exit(2);
  }

  if(results["output"] != null) {
    _outputPath = results["output"];
  }

  D2Api.debug = results["verbose"];
  d2api = D2Api(apikey: apikey);
  d2api.initManifest("manifest.json");

  MemberInfoResult member;
  try {
    member = await d2api.getMemberInfo(gamertag, platformId);
  } catch(e) {
    print("Error calling API. ${e.runtimeType}");
    exit(2);
  }

  List<Character> characters;

  try {
    characters = await d2api.getCharacters(member.memberId, platformId);
  } catch(e) {
    print("Error calling API. ${e.runtimeType}");
    exit(2);
  }

  bool hunter = results["hunter"];
  bool titan = results["titan"];
  bool warlock = results["warlock"];

  bool filterByClass = hunter || titan || warlock;

  int failedCount = 0;
  List<GameReportContainer> reports = [];
  for(Character c in characters) {

    if(filterByClass) {
      if(
        !((c.classType == ClassType.hunter && hunter) || 
        (c.classType == ClassType.titan && titan) || 
        (c.classType == ClassType.warlock && warlock))){
        continue;
      }
    }

    print("Loading games for ${ClassType.labelFromType(c.classType)}");

    List<int> ids;
    try {
      ids = await d2api.getActivityIds(member.memberId, platformId, c.id);
    } catch(e) {
      print("Could not retrieve activity ids. ${e.runtimeType}");
      exit(2);
    }

    print("Found ${ids.length} games for ${ClassType.labelFromType(c.classType)}");

    for(int i = 0; i < ids.length;){

      List<Future> futures = [];
      int diff = ids.length - i;
      int max = (diff > _downloadBatchCount)?_downloadBatchCount:diff;

      for(int k = 0; k < max; k++) {
        print("Loading ${i} of ${ids.length}");
        int id = ids[i];

        Future<void> Function() f = () async {
          try{
            GameReport report = await d2api.getPostGameReport(id, c.id);
            GameReportContainer container = GameReportContainer(classType: c.classType, report: report);
            reports.add(container);
          } catch(e) {
            print("Could not retrieve activity : $id");
            failedCount++;
          }
        };

        futures.add(f());
        i++;
      }

      await Future.wait(futures);

    }
  }

  reports.sort((a,b){
    return a.report.period.compareTo(b.report.period);
  });

  if(failedCount > 0) {
    print("WARNING: $failedCount ${failedCount == 1?"activity":"activities"} could not be retrieved.");
  }

  bool exportJson = results["json"];
  bool exportCsv = results["csv"];

  if(!exportCsv && !exportJson) {
    exportCsv = true;
  }

  if(exportCsv) {
    print("Writing CSV file.");
    await writeCSV("$_outputPath.csv", reports);
  }

  if(exportJson) {
    print("Writing JSON file.");
    await writeJSON("$_outputPath.json", reports);
  }

  exit(1);
}

Future<void> writeJSON(String path, List<GameReportContainer> reports) async {

  StringBuffer b = StringBuffer("[");
  for(GameReportContainer c in reports) {
    b.write(c.toJson());

    if(c != reports.last) {
      b.write(",");
    }
  }
  b.write("]");

  String json = '{'
      '"reports": ${b.toString()}'
    '}';

  //hack to pretty print the json
  Map<String, dynamic> tmp = jsonDecode(json);
  json = jsonEncode(tmp);

  File f = new File(path);
  await f.writeAsString(json);
}

Future<void> writeCSV(String path, List<GameReportContainer> reports) async {

  StringBuffer buffer = StringBuffer(createCSVHeader());
  for(GameReportContainer c in reports) {
    buffer.write(createCSVRow(c.report, c.classType));
  }

  String csv = buffer.toString();

  File f = new File(path);
  await f.writeAsString(csv);
}

String createCSVHeader() {

  String out = "ID$_seperator"
        "CLASS$_seperator"
        "ABILITY_KILLS$_seperator"
        "ACTIVITY_DURATION$_seperator" 
        "ASSISTS$_seperator"
        "AVG_SCORE_PER_KILL$_seperator"
        "AVG_SCORE_PER_LIFE$_seperator"
        "COMPLETED$_seperator"
        "DEATHS$_seperator"
        "EFFICIENCY$_seperator"
        "EXPERIENCE_TYPE$_seperator"
        "GRENADE_KILLS$_seperator"
        "KILLS$_seperator"
        "KILLS_DEATHS_RATIO$_seperator"
        "KILLS_DEATHS_ASSISTS_RATIO$_seperator"
        "MAP_NAME$_seperator"
        //"${report.medalResults},"
        "MELEE_KILLS$_seperator"
        "MODE$_seperator"
        "OPPONENT_SCORE$_seperator"
        "OPPONENTS_DEFEATED$_seperator"
        "DATE$_seperator"
        "PRECISION_KILLS$_seperator"
        "RESULT$_seperator"
        "SCORE$_seperator"
        "SUPER_KILLS$_seperator"
        "TEAM_SCORE$_seperator"
        "TIME_PLAYED$_seperator"
        "MEDALS_EARNED$_seperator"
        "$_lineSeperator";
        //"${report.weaponResults}";
      return out;
}

String createCSVRow(GameReport report, int classType) {

  String classLabel = ClassType.labelFromType(classType);
  String experienceType = (report.experienceType == ExperienceType.valor)?"Valor":"Glory";
  String out = "${report.id}$_seperator"
        "$classLabel$_seperator"
        "${report.abilityKills}$_seperator"
        "${report.activityDurationSeconds}$_seperator" 
        "${report.assists}$_seperator"
        "${report.averageScorePerKill}$_seperator"
        "${report.averageScorePerLife}$_seperator"
        "${report.completed}$_seperator"
        "${report.deaths}$_seperator"
        "${report.efficiency}$_seperator"
        "$experienceType$_seperator"
        "${report.grenadeKills}$_seperator"
        "${report.kills}$_seperator"
        "${report.killsDeaths}$_seperator"
        "${report.killsDeathsAssists}$_seperator"
        "${report.mapName}$_seperator"
        //"${report.medalResults}$_seperator"
        "${report.meleeKills}$_seperator"
        "${report.modeName}$_seperator"
        "${report.opponentScore}$_seperator"
        "${report.opponentsDefeated}$_seperator"
        "${report.period}$_seperator"
        "${report.precisionKills}$_seperator"
        "${report.resultDisplay}$_seperator"
        "${report.score}$_seperator"
        "${report.superKills}$_seperator"
        "${report.teamScore}$_seperator"
        "${report.timePlayedSeconds}$_seperator"
        "${report.totalMedalsEarned}$_seperator"
        "$_lineSeperator";
        //"${report.weaponResults}";
      return out;
}

void printUsage() {
  print(
    "dart ec.dart --apikey APIKEY --platform [xbox|psn|steam] --tag "
    "[GAMERTAG|STEAM64ID) [--verbose] [--hunter|--titan|--warlock] [--csv|--json] "
    "[--output OUTPUTPATH]"
    "[--help]"
    );
}

class GameReportContainer {
  int classType;
  GameReport report;

  GameReportContainer({this.classType, this.report});

  String toJson() {
    return '{'
      '"classType":"${ClassType.labelFromType(classType)}",'
      '"report":${report.toJson()}'
      '}';
  }
}
