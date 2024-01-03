### bluetoothctl configuration

A batch of commands to run in `bluetoothctl`'s interactive mode to setup a simple
peripheral to test stuff. One day I'll figure out how to script this. 🤷

```shell
# start bluetoothctl
menu advertise
manufacturer 0xFFFF 0x01 0x02 0x03
name shackleford
back
menu gatt
register-service 5FA712B2-2CA5-45AD-B0DA-6CE2A8CA9DD0
register-characteristic 0x1234 read
register-characteristic 0x5678 read,write
register-application
back
advertise on
menu advertise
service 5FA712B2-2CA5-45AD-B0DA-6CE2A8CA9DD0
uuids 5FA712B2-2CA5-45AD-B0DA-6CE2A8CA9DD0
back
```
