async = require 'async'
axon = require 'axon'
Exc       = require 'jsDAV/lib/shared/exceptions'
WebdavAccount = require '../models/webdavaccount'


handle    = (err) ->
    console.log err
    return new Exc.jsDAV_Exception err.message || err

module.exports = class CozyCardDAVBackend

    constructor: (@Contact) ->

        @getLastCtag (err, ctag) =>
            # we suppose something happened while webdav was down
            @ctag = ctag + 1
            @saveLastCtag @ctag

            onChange = =>
                @ctag = @ctag + 1
                @saveLastCtag @ctag

            # keep ctag updated
            socket = axon.socket 'sub-emitter'
            socket.connect 9105
            socket.on 'contact.*', onChange

    getLastCtag: (callback) ->
        WebdavAccount.first (err, account) ->
            callback err, account?.cardctag or 0

    saveLastCtag: (ctag, callback = ->) =>
        WebdavAccount.first (err, account) =>
            return callback err if err or not account
            account.updateAttributes cardctag: ctag, ->

    getAddressBooksForUser: (principalUri, callback) ->
        book =
            id: 'all-contacts'
            uri: 'all-contacts'
            principaluri: principalUri
            "{http://calendarserver.org/ns/}getctag": @ctag
            "{DAV:}displayname": 'Cozy Contacts'

        return callback null, [book]

    getCards: (addressbookId, callback) ->
        @Contact.all (err, contacts) ->
            return callback handle err if err
            async.mapSeries contacts, (contact, next) ->
                contact.toVCF (err, vCardOutput) ->
                    next err,
                        lastmodified: 0
                        carddata: vCardOutput
                        uri: contact.getURI()
            , callback

    getCard: (addressBookId, cardUri, callback) ->
        @Contact.byURI cardUri, (err, contact) ->
            return callback handle err if err
            return callback null unless contact.length

            contact = contact[0]
            contact.toVCF (err, vCardOutput) ->
                callback null,
                    lastmodified: 0
                    carddata: vCardOutput
                    uri: contact.getURI()

    createCard: (addressBookId, cardUri, cardData, callback) ->
        data = @Contact.parse cardData
        data.carddavuri = cardUri
        @Contact.create data, (err, contact) ->
            return callback handle err if err?
            contact.handlePhoto data.photo, callback

    updateCard: (addressBookId, cardUri, cardData, callback) ->
        @Contact.byURI cardUri, (err, contact) =>
            return callback handle err if err
            return callback handle 'Not Found' unless contact.length

            contact = contact[0]
            data = @Contact.parse cardData
            data.id = contact._id
            data.carddavuri = cardUri

            # @TODO: fix during cozydb migration
            # Surprinsingly updateAttributes has no effect without this pre-fill
            for k, v of data
                contact[k] = v
            contact.updateAttributes data, (err, contact) ->
                return callback handle err if err?
                contact.handlePhoto data.photo, callback

    deleteCard: (addressBookId, cardUri, callback) ->
        @Contact.byURI cardUri, (err, contact) ->
            return callback handle err if err

            contact = contact[0]

            contact.destroy (err) ->
                return callback handle err if err

                callback null
