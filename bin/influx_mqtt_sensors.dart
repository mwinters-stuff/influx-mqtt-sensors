import 'dart:convert';
import 'dart:io' show Platform, exit;
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

final MQTT_FEED_TEMPERATURE = 'garagedoor/report/temperature';
final MQTT_FEED_DOOR_POSITION = 'garagedoor/report/door_position';
final MQTT_FEED_DOOR_SONIC_CM = 'garagedoor/report/sonic_cm';
double lastSonicDistance = -1.0;

Future<List<List<dynamic>>> getFromInflux(Map<String, String> env) async {
  var headers = {
    'Authorization': 'Token ${env['INFLUX_TOKEN']}',
    'Content-Type': 'application/vnd.flux'
  };

  var request = http.Request('POST',
      Uri.parse('${env['INFLUX_URL']}/api/v2/query?org=${env['INFLUX_ORG']}'));

  request.body = '''from(bucket: "${env['INFLUX_BUCKET']}")
  |> range(start:-24h)
  |> filter(fn: (r) => r["_measurement"] == "sensor-data" or r["_measurement"] == "flick-electric")
  |> filter(fn: (r) => r["_field"] == "dew-point" or r["_field"] == "humidity" 
      or r["_field"] == "light" or r["_field"] == "rain"
      or r["_field"] == "pressure" or r["_field"] == "temperature" or r["_field"] == "wind" 
      or r["_field"] == "wind-direction" or r["_field"] == "wind-direction-str" 
      or r["_field"] == "wind-gust" or r["_field"] == "wind-gust-direction" 
      or r["_field"] == "wind-gust-direction-str" or r["_field"] == "total-cents-kwh")
  |> last()''';

  request.headers.addAll(headers);

  var response = await request.send();

  if (response.statusCode == 200) {
    var rowsAsListOfValues =
        utf8.decoder.bind(response.stream).transform(CsvToListConverter());
    final result = <List<dynamic>>[];

    await rowsAsListOfValues.forEach((element) {
      var sublist = element.sublist(1);
      if (sublist.isNotEmpty && sublist[0] != 'result') {
        var v;
        if (sublist.length == 8) {
          v = sublist.sublist(5);
        } else {
          v = sublist.sublist(5, 9);
          v.removeAt(2);
        }
        print(v);
        result.add(v);
      }
    });
    return Future.value(result);
  }
  return Future.error(response.reasonPhrase!);
}

void messagePublished(
    Map<String, String> env, MqttPublishMessage message) async {
  print(
      'Published notification:: topic is ${message.variableHeader!.topicName}, with Qos ${message.header!.qos}');
  var headers = {'Authorization': 'Token ${env['INFLUX_TOKEN']}'};

  var request = http.Request(
      'POST',
      Uri.parse(
          '${env['INFLUX_URL']}/api/v2/write?org=${env['INFLUX_ORG']}&bucket=${env['INFLUX_BUCKET']}&precision=s'));
  request.headers.addAll(headers);
  final messageStr =
      AsciiPayloadConverter().convertFromBytes(message.payload.message!);

  if (message.variableHeader!.topicName == MQTT_FEED_TEMPERATURE) {
    request.body =
        'sensor-data,location=garage,sensor=environmental temperature=$messageStr';
  }
  if (message.variableHeader!.topicName == MQTT_FEED_DOOR_POSITION) {
    request.body = 'garage-door,door=left door-position=$messageStr';
  }
  if (message.variableHeader!.topicName == MQTT_FEED_DOOR_SONIC_CM) {
    var distance = double.tryParse(messageStr);
    if (distance != null && distance != lastSonicDistance) {
      request.body = 'garage-door,door=left sonic-distance=$distance';
      lastSonicDistance = distance;
    }
  }
  if (request.body.isNotEmpty) {
    print('sending ${request.body}');
    var response = await request.send();
    print('Response: ${response.statusCode} -> ${response.reasonPhrase}');
  }
}

void main(List<String> arguments) async {
  final env = Platform.environment;

  final mqttClient = MqttServerClient.withPort(
      env['MQTT_HOSTNAME']!, 'mqtt-inflsux', int.parse(env['MQTT_PORT']!));
  mqttClient.logging(on: false);
  mqttClient.keepAlivePeriod = 20;
  mqttClient.autoReconnect = true;
  mqttClient.onAutoReconnect = () => print('onAutoReconnect');
  mqttClient.onDisconnected = () => print('onDisconnect');
  mqttClient.onConnected = () => print('onConnected');
  mqttClient.onAutoReconnected = () => print('onAutoReconnected');
  mqttClient.onSubscribed = (topic) => print('onSubscribed to $topic');
  mqttClient.onSubscribeFail = (topic) => print('onSubscribeFail to $topic');
  mqttClient.onUnsubscribed = (topic) => print('onUnsubscribed from $topic');

  try {
    await mqttClient.connect(env['MQTT_USERNAME']!, env['MQTT_PASSWORD']!);
  } on Exception catch (e) {
    print('EXAMPLE::client exception - $e');
    mqttClient.disconnect();
    exit(1);
  }

  mqttClient.subscribe(MQTT_FEED_DOOR_POSITION, MqttQos.atMostOnce);
  mqttClient.subscribe(MQTT_FEED_DOOR_SONIC_CM, MqttQos.atMostOnce);
  mqttClient.subscribe(MQTT_FEED_TEMPERATURE, MqttQos.atMostOnce);

  mqttClient.published!.listen((message) => messagePublished(env, message));

  while (true) {
    final data = await getFromInflux(env);
    data.forEach((element) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(element[0].toString());

      mqttClient.publishMessage('sensors/${element[1]}/${element[2]}',
          MqttQos.atLeastOnce, builder.payload!);
    });
    print('sleeping');
    await MqttUtilities.asyncSleep(60);
  }
}
