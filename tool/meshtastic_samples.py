# SPDX-License-Identifier: MPL-2.0
# (c) SDUBOS Consulting et contributeurs SARCADE
#
# Lot 28: sample Meshtastic messages of test/fixtures/meshtastic_frames.dart,
# encoded by Google protobuf (pip install protobuf) from a minimal schema
# written here (field numbers of the public client API; no Meshtastic
# .proto file, GPL-3.0, is used). Run: python3 tool/meshtastic_samples.py
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
F=descriptor_pb2.FieldDescriptorProto
fd=descriptor_pb2.FileDescriptorProto(name='mini.proto',package='mini',syntax='proto3')
def msg(name,fields,oneof=None):
    m=fd.message_type.add(name=name)
    if oneof: m.oneof_decl.add(name=oneof)
    for (n,num,t,tn,*o) in fields:
        f=m.field.add(name=n,number=num,type=t,label=F.LABEL_OPTIONAL)
        if tn: f.type_name='.mini.'+tn
        if o and o[0]=='oneof': f.oneof_index=0
T=F
msg('User',[('id',1,T.TYPE_STRING,None),('long_name',2,T.TYPE_STRING,None),('short_name',3,T.TYPE_STRING,None),('hw_model',5,T.TYPE_INT32,None),('is_licensed',6,T.TYPE_BOOL,None),('role',7,T.TYPE_INT32,None),('public_key',8,T.TYPE_BYTES,None)])
msg('Position',[('latitude_i',1,T.TYPE_SFIXED32,None),('longitude_i',2,T.TYPE_SFIXED32,None),('altitude',3,T.TYPE_INT32,None),('time',4,T.TYPE_FIXED32,None)])
msg('DeviceMetrics',[('battery_level',1,T.TYPE_UINT32,None),('voltage',2,T.TYPE_FLOAT,None),('channel_utilization',3,T.TYPE_FLOAT,None),('air_util_tx',4,T.TYPE_FLOAT,None),('uptime_seconds',5,T.TYPE_UINT32,None)])
msg('Telemetry',[('time',1,T.TYPE_FIXED32,None),('device_metrics',2,T.TYPE_MESSAGE,'DeviceMetrics')])
msg('NodeInfo',[('num',1,T.TYPE_UINT32,None),('user',2,T.TYPE_MESSAGE,'User'),('position',3,T.TYPE_MESSAGE,'Position'),('snr',4,T.TYPE_FLOAT,None),('last_heard',5,T.TYPE_FIXED32,None),('device_metrics',6,T.TYPE_MESSAGE,'DeviceMetrics'),('via_mqtt',8,T.TYPE_BOOL,None),('hops_away',9,T.TYPE_UINT32,None)])
msg('Data',[('portnum',1,T.TYPE_INT32,None),('payload',2,T.TYPE_BYTES,None),('want_response',3,T.TYPE_BOOL,None),('request_id',6,T.TYPE_FIXED32,None)])
msg('MeshPacket',[('from',1,T.TYPE_FIXED32,None),('to',2,T.TYPE_FIXED32,None),('channel',3,T.TYPE_UINT32,None),('decoded',4,T.TYPE_MESSAGE,'Data','oneof'),('encrypted',5,T.TYPE_BYTES,None,'oneof'),('id',6,T.TYPE_FIXED32,None),('rx_time',7,T.TYPE_FIXED32,None),('rx_snr',8,T.TYPE_FLOAT,None),('hop_limit',9,T.TYPE_UINT32,None),('want_ack',10,T.TYPE_BOOL,None),('rx_rssi',12,T.TYPE_INT32,None),('via_mqtt',14,T.TYPE_BOOL,None),('hop_start',15,T.TYPE_UINT32,None)],oneof='payload_variant')
msg('MyNodeInfo',[('my_node_num',1,T.TYPE_UINT32,None),('reboot_count',8,T.TYPE_UINT32,None)])
msg('DeviceMetadata',[('firmware_version',1,T.TYPE_STRING,None),('device_state_version',2,T.TYPE_UINT32,None),('hw_model',9,T.TYPE_INT32,None)])
msg('LoRaConfig',[('use_preset',1,T.TYPE_BOOL,None),('modem_preset',2,T.TYPE_INT32,None),('region',7,T.TYPE_INT32,None),('hop_limit',8,T.TYPE_UINT32,None),('tx_enabled',9,T.TYPE_BOOL,None),('tx_power',10,T.TYPE_INT32,None)])
msg('Config',[('lora',6,T.TYPE_MESSAGE,'LoRaConfig')])
msg('ChannelSettings',[('psk',2,T.TYPE_BYTES,None),('name',3,T.TYPE_STRING,None)])
msg('Channel',[('index',1,T.TYPE_INT32,None),('settings',2,T.TYPE_MESSAGE,'ChannelSettings'),('role',3,T.TYPE_INT32,None)])
msg('QueueStatus',[('res',1,T.TYPE_INT32,None),('free',2,T.TYPE_UINT32,None),('maxlen',3,T.TYPE_UINT32,None),('mesh_packet_id',4,T.TYPE_UINT32,None)])
msg('Routing',[('error_reason',3,T.TYPE_INT32,None,'oneof')],oneof='variant')
msg('Heartbeat',[])
msg('FromRadio',[('id',1,T.TYPE_UINT32,None),('packet',2,T.TYPE_MESSAGE,'MeshPacket','oneof'),('my_info',3,T.TYPE_MESSAGE,'MyNodeInfo','oneof'),('node_info',4,T.TYPE_MESSAGE,'NodeInfo','oneof'),('config',5,T.TYPE_MESSAGE,'Config','oneof'),('config_complete_id',7,T.TYPE_UINT32,None,'oneof'),('rebooted',8,T.TYPE_BOOL,None,'oneof'),('channel',10,T.TYPE_MESSAGE,'Channel','oneof'),('queueStatus',11,T.TYPE_MESSAGE,'QueueStatus','oneof'),('metadata',13,T.TYPE_MESSAGE,'DeviceMetadata','oneof')],oneof='payload_variant')
msg('ToRadio',[('packet',1,T.TYPE_MESSAGE,'MeshPacket','oneof'),('want_config_id',3,T.TYPE_UINT32,None,'oneof'),('disconnect',4,T.TYPE_BOOL,None,'oneof'),('heartbeat',7,T.TYPE_MESSAGE,'Heartbeat','oneof')],oneof='payload_variant')
pool=descriptor_pool.DescriptorPool(); pool.Add(fd)
M={m.name:message_factory.GetMessageClass(pool.FindMessageTypeByName('mini.'+m.name)) for m in fd.message_type}
def h(m): return m.SerializeToString().hex()
out={}
fr=M['FromRadio'](); fr.my_info.my_node_num=0xa1b2c3d4; out['myInfo']=h(fr)
fr=M['FromRadio'](); fr.metadata.firmware_version='2.6.11.60ec05e'; fr.metadata.hw_model=43; out['metadata']=h(fr)
fr=M['FromRadio'](); l=fr.config.lora; l.use_preset=True; l.modem_preset=0; l.region=3; l.hop_limit=3; l.tx_enabled=True; l.tx_power=-2; out['loraConfig']=h(fr)
fr=M['FromRadio'](); fr.channel.index=0; fr.channel.settings.psk=b'\x01'; fr.channel.settings.name=''; fr.channel.role=1; out['channelPrimary']=h(fr)
fr=M['FromRadio'](); fr.channel.index=1; fr.channel.settings.name='ADRASEC'; fr.channel.role=2; out['channelSecondary']=h(fr)
fr=M['FromRadio'](); n=fr.node_info; n.num=0xa1b2c3d4; n.user.id='!a1b2c3d4'; n.user.long_name='F4ABC Mobile'; n.user.short_name='F4AB'; n.user.hw_model=43; n.position.latitude_i=487654321; n.position.longitude_i=19876543; n.position.altitude=152; n.snr=0; n.last_heard=1793800000; n.device_metrics.battery_level=18; n.device_metrics.voltage=3.62; out['nodeMe']=h(fr)
fr=M['FromRadio'](); n=fr.node_info; n.num=0x0badcafe; n.user.id='!0badcafe'; n.user.long_name='Relais Maurepas'; n.user.short_name='RMAU'; n.user.hw_model=9; n.user.role=2; n.position.latitude_i=487800000; n.position.longitude_i=19500000; n.snr=6.25; n.last_heard=1793799000; n.device_metrics.battery_level=101; n.hops_away=2; out['nodeRouter']=h(fr)
fr=M['FromRadio'](); n=fr.node_info; n.num=0x12345678; n.user.long_name='Sans position'; n.snr=-7.5; n.last_heard=1793790000; out['nodeNoPos']=h(fr)
fr=M['FromRadio'](); fr.config_complete_id=42; out['configComplete']=h(fr)
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0x0badcafe); p.to=0xa1b2c3d4; p.channel=0; p.decoded.portnum=1; p.decoded.payload='Bonjour Gérard'.encode(); p.id=0x01020304; p.rx_time=1793800100; p.rx_snr=-3.5; p.hop_limit=1; p.hop_start=3; p.rx_rssi=-97; out['textDirect']=h(fr)
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0x12345678); p.to=0xffffffff; p.channel=0; p.decoded.portnum=1; p.decoded.payload=b'Point radio 12 OK'; p.id=0x0a0b0c0d; p.rx_time=1793800200; p.hop_limit=3; p.hop_start=3; out['textChannel']=h(fr)
r=M['Routing'](); r.error_reason=0
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0x0badcafe); p.to=0xa1b2c3d4; p.decoded.portnum=5; p.decoded.payload=r.SerializeToString(); p.decoded.request_id=0x11223344; p.id=0x55667788; out['ackDelivered']=h(fr)
r=M['Routing'](); r.error_reason=5
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0xa1b2c3d4); p.to=0xa1b2c3d4; p.decoded.portnum=5; p.decoded.payload=r.SerializeToString(); p.decoded.request_id=0x11223344; out['nakMaxRetransmit']=h(fr)
pos=M['Position'](); pos.latitude_i=487000000; pos.longitude_i=21000000; pos.time=1793800300
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0x12345678); p.to=0xffffffff; p.decoded.portnum=3; p.decoded.payload=pos.SerializeToString(); p.rx_time=1793800300; p.hop_limit=2; p.hop_start=3; out['positionPacket']=h(fr)
t=M['Telemetry'](); t.time=1793800400; t.device_metrics.battery_level=9; t.device_metrics.voltage=3.4
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0xa1b2c3d4); p.to=0xffffffff; p.decoded.portnum=67; p.decoded.payload=t.SerializeToString(); out['telemetryMe']=h(fr)
fr=M['FromRadio'](); p=fr.packet; setattr(p,'from',0x0badcafe); p.to=0xffffffff; p.channel=1; p.encrypted=b'\x99\x88\x77'; p.id=7; out['encrypted']=h(fr)
fr=M['FromRadio'](); fr.queueStatus.res=0; fr.queueStatus.free=15; fr.queueStatus.maxlen=16; fr.queueStatus.mesh_packet_id=0x11223344; out['queue']=h(fr)
fr=M['FromRadio'](); fr.rebooted=True; out['rebooted']=h(fr)
# ToRadio expected encodings
tr=M['ToRadio'](); tr.want_config_id=12345; out['wantConfig12345']=h(tr)
tr=M['ToRadio'](); tr.heartbeat.SetInParent(); out['heartbeat']=h(tr)
tr=M['ToRadio'](); tr.disconnect=True; out['disconnect']=h(tr)
tr=M['ToRadio'](); p=tr.packet; p.to=0x0badcafe; p.decoded.portnum=1; p.decoded.payload='Reçu, 5 sur 5'.encode(); p.id=0x11223344; p.want_ack=True; out['sendDirect']=h(tr)
tr=M['ToRadio'](); p=tr.packet; p.to=0xffffffff; p.channel=0; p.decoded.portnum=1; p.decoded.payload=b'A tous'; p.id=0x7fffffff; p.want_ack=True; out['sendChannel']=h(tr)
# negative int32 varint check
q=M['QueueStatus'](); q.res=-1; out['queueNeg']=M['FromRadio'](queueStatus=q).SerializeToString().hex()
for k,v in out.items(): print(f"  '{k}':'{v}',")
