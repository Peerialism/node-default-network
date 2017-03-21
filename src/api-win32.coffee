net = require('net')
exec = require('child_process').exec
async = require('async')
parseCSV = require('csv-parse')

wmic = (cls, keys, callback) ->
  command = "wmic path #{cls} get #{keys.join(',')} /format:csv"
  exec command, (error, stdout, stderr) ->
    return callback(error) if error?
    parseCSV stdout, {
      columns: true
      rowDelimiter: '\r\r\n'
      skip_empty_lines: true
      trim: true
    } , (error, records) ->
      callback(error, records)

getAdapterConfig = (callback) ->
  wmic 'Win32_NetworkAdapterConfiguration',
    ['Index', 'IPEnabled', 'DefaultIPGateway','Description'],
    (error, records) ->
      callback(error, records)

getAdapter = (callback) ->
  wmic 'Win32_NetworkAdapter',
    ['Index', 'NetConnectionID','AdapterType'],
    (error, records) ->
      callback(error, records)

getDefaultGateway = (callback) ->
  getAdapterConfig (error, records) ->
    return callback(error) if error?
    data = {}
    for record in records
      continue if not record['IPEnabled']?
      continue if not record['DefaultIPGateway']?
      continue if not record['Index']?
      continue if not record['Description']?
      continue if record['IPEnabled'] != 'TRUE'
      continue if record['DefaultIPGateway'].trim() == ''
      continue if isNaN(parseInt(record['Index']))
      index = record['Index']
      defaultGateway = record['DefaultIPGateway'].trim()
      defaultGateway = ((defaultGateway.match(/{(.*)}/) || [])[1] || '')
      for address in defaultGateway.split(';')
        switch net.isIP(address)
          when 4
            data[index] || = []
            data[index].push {family: 'IPv4', address: address, description: record['Description']}
          when 6
            data[index] || = []
            data[index].push {family: 'IPv6', address: address, description: record['Description']}
          else
            return callback(new Error("#{address} is not IP address"))
    callback(null, data)

getAdapterNameByIndex = (index, callback) ->
  getAdapter (error, records) ->
    return callback(error) if error?
    for record in records
      if record['Index'] == index
        returnRecord = {netConnectionId: record['NetConnectionID'], adapterType: record['AdapterType']}
        return callback(null, returnRecord)
    callback(new Error("inteface #{index} is not available"))

getDefaultNetwork = (callback) ->
  getDefaultGateway (error, gateways) ->
    return callback(error) if error?
    indexes = Object.keys(gateways)
    async.map indexes,
      (index, callback) ->
        getAdapterNameByIndex index, (error, name) ->
          return callback(error) if error?
          iface = {index: index, name: name.netConnectionId, adapterType: name.adapterType}
          callback(null, iface)
      (error, ifaces) ->
        return callback(error) if error?
        data = {}
        for iface in ifaces
          data[iface.name] = [{family: gateways[iface.index][0].family, address: gateways[iface.index][0].address, description: gateways[iface.index][0].description, adapterType: iface.adapterType}]
        callback(null, data)

collect = (callback) ->
  getDefaultNetwork (error, data) ->
    return callback(null, {} ) if error?
    callback(null, data)

module.exports =
  collect: collect
