#!/usr/bin/perl
#
# LJ::TextMessage class
# See perldoc documentation at the end of this file.
#
# -------------------------------------------------------------------------
#
# This package is released under the LGPL (GNU Library General Public License)
#
# A copy of the license has been included with the software as LGPL.txt.
# If not, the license is available at:
#      http://www.gnu.org/copyleft/library.txt
#
# -------------------------------------------------------------------------
#

package LJ::TextMessage;

use URI::Escape;  # FIXME: don't use this (uri_escape() below), when we have LJ::eurl() as our standard
use  HTTP::Request;
use  LWP::UserAgent;
use  MIME::Lite;

use strict;
use vars qw($VERSION %providers);

$VERSION = '1.5.6';

%providers = (

    'email' => {
        'name'       => 'Other',
        'notes'      => 'If your provider isn\'t supported directly, enter the email address that sends you a text message in phone number field. To be safe, the entire message is sent in the body of the message, and the length limit is really short. We\'d prefer you give us information about your provider so we can support it directly.',
        'fromlimit'  => 15,
        'msglimit'   => 100,
        'totlimit'   => 100,
    },

    'airtouch' => {
        'name'       => 'Verizon Wireless (formerly Airtouch)',
        'notes'      => 'Enter your phone number. Messages are sent to number@airtouchpaging.com. This is ONLY for former AirTouch customers. Verizon Wireless customers should use Verizon Wireless instead.',
        'fromlimit'  => 20,
        'msglimit'   => 120,
        'totlimit'   => 120,
    },

    'aliant' => {
        'name'          => 'Aliant (NBTel, MTT, NewTel, and Island Tel)',
        'notes'         => 'Enter your phone number. Message is sent to number@chat.wirefree.ca',
        'fromlimit'     => 11,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'alltel' => {
        'name'          => 'Alltel',
        'notes'         => 'Enter your phone number. Goes to number@message.alltel.com.',
        'fromlimit'     => 50,
        'msglimit'      => 116,
        'totlimit'      => 116,
    },

    'ameritech' => {
        'name'          => 'Ameritech (ACSWireless)',
        'notes'         => 'Enter your phone number. Goes to number@paging.acswireless.com',
        'fromlimit'     => 120,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'arch' => {
        'name'          => 'Arch Wireless',
        'notes'         => 'Enter your phone number. Sent via http://www.arch.com/message/ (assumes blank PIN)',
        'fromlimit'     => 15,
        'msglimit'      => 240,
        'totlimit'      => 240,
    },

    'att' =>
    {
        'name'          => 'AT&T',
        'notes'         => 'Enter your phone number. Goes to number@txt.att.net',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'aubykddi' => {
        'name'          => 'AU by KDDI',
        'notes'         => 'Enter your phone number. Goes to username@ezweb.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 10000,
        'totlimit'      => 10000,
    },

    'bellmobilityca' => {
        'name'          => 'Bell Mobility Canada',
        'notes'         => 'Enter your phone number, including the 1 prefix. Goes to number@txt.bellmobility.ca',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'beemail' => {
        'name'          => 'BeeLine GSM',
        'notes'         => 'Enter your phone number. Goes to number@sms.beemail.ru',
        'fromlimit'     => 50,
        'msglimit'      => 255,
        'totlimit'      => 255,
    },

    'bellsouth' => {
        'name'          => 'Bellsouth',
        'notes'         => 'Enter your phone number. Goes to number@bellsouth.cl',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'bellsouthmobility' => {
        'name'          => 'BellSouth Mobility',
        'notes'         => 'Enter your phone number. Goes to number@blsdcs.net',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'blueskyfrog' => {
        'name'          => 'Blue Sky Frog',
        'notes'         => 'Enter your phone number. Goes to number@blueskyfrog.com',
        'fromlimit'     => 30,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'boost' => {
        'name'          => 'Boost',
        'notes'         => 'Enter your phone number. Goes to number@myboostmobile.com',
        'fromlimit'     => 30,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'cellularonedobson' => {
        'name'          => 'CellularOne (Dobson)',
        'notes'         => 'Enter your phone number. Goes to number@mobile.celloneusa.com',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'cellularonewest' => {
        'name'          => 'CellularOne West',
        'notes'         => 'Enter your phone number. Goes to number@mycellone.com',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'centennial' => {
        'name'          => 'Centennial Wireless',
        'notes'         => 'Enter your phone number. Sent via http://www.centennialwireless.com',
        'fromlimit'     => 10,
        'msglimit'      => 110,
        'totlimit'      => 110,
    },

    'cincinnatibell' => {
        'name'          => 'Cincinnati Bell',
        'notes'         => 'Enter your phone number. Goes to number@gocbw.com',
        'fromlimit'     => 20,
        'msglimit'      => 50,
        'totlimit'      => 50,
    },

    'claro' =>
    {
        'name'          => 'Claro',
        'notes'         => 'Enter your phone number. Goes to number@clarotorpedo.com.br',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'comviq' =>
    {
        'name'          => 'Comviq',
        'notes'         => 'Enter your phone number. Goes to number@sms.comviq.se',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'csouth1' => {
        'name'          => 'Cellular South',
        'notes'         => 'Enter your phone number. Messages are sent to number@csouth1.com',
        'fromlimit'     => 50,
        'msglimit'      => 155,
        'totlimit'      => 155,
    },

    'dutchtone' => {
        'name'          => 'Dutchtone/Orange-NL',
        'notes'         => 'Enter your phone number. Messages are sent to number@sms.orange.nl',
        'fromlimit'     => 15,
        'msglimit'      => 150,
        'totlimit'      => 150,
    },

    'edgewireless' => {
        'name'          => 'Edge Wireless',
        'notes'         => 'Enter your phone number. Messages are sent to number@sms.edgewireless.com',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'einstein' => {
        'name'          => 'EinsteinPCS / Airadigm Communications',
        'notes'         => 'Enter your phone number. Messages are sent to number@einsteinsms.com',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'emt' => {
        'name'          => 'Estonia Mobile Telefon',
        'notes'         => 'Enter your phone number. Sent via webform.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'eplus' => {
        'name'          => 'EPlus',
        'notes'         => 'Enter your phone number. Goes to number@smsmail.eplus.de.',
        'fromlimit'     => 20,
        'msglimit'      => 480,
        'totlimit'      => 480,
    },

    'fidoca' => {
        'name'          => 'Fido Canada',
        'notes'         => 'Enter your phone number. Goes to number@fido.ca.',
        'fromlimit'     => 15,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'goldentelecom' => {
        'name'          => 'Golden Telecom',
        'notes'         => 'Enter your phone number or nickname. Messages are sent to number@sms.goldentele.com',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'ideacellular' => {
        'name'          => 'Idea Cellular',
        'notes'         => 'Enter your phone number. Messages are sent to number@ideacellular.net',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
        },

    'kyivstar' => {
        'name'          => 'Kyivstar',
        'notes'         => 'Sent by addressing the message to number@sms.kyivstar.net',
        'fromlimit'     => 30,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'lmt' => {
        'name'          => 'LMT',
        'notes'         => 'Enter your username. Goes to username@sms.lmt.lv',
        'fromlimit'     => 30,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'meteor' => {
        'name'          => 'Meteor',
        'notes'         => 'Enter your phone number. Goes to number@sms.mymeteor.ie',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'metrocall' => {
        'name'          => 'Metrocall Pager',
        'notes'         => '10-digit phone number. Goes to number@page.metrocall.com',
        'fromlimit'     => 120,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'metropcs' => {
        'name'          => 'Metro PCS',
        'notes'         => '10-digit phone number. Goes to number@mymetropcs.com',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'movistar' => {
        'name'          => 'Telefonica Movistar',
        'notes'         => '10-digit phone number. Goes to number@movistar.net',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'mtsmobility' => {
        'name'          => 'Manitoba Telecom Systems',
        'notes'         => '10-digit phone number. Goes to @text.mtsmobility.com',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'mtsprimtel' => {
        'name'          => 'MTS Primtel',
        'notes'         => 'Enter your phone number. Sent via web gateway.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'mobileone' => {
        'name'          => 'MobileOne',
        'notes'         => 'Enter your phone number. Goes to number@m1.com.sg',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'mobilfone' => {
        'name'          => 'Mobilfone',
        'notes'         => 'Enter your phone number. Goes to number@page.mobilfone.com',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'mobility' => {
        'name'          => 'Mobility Bermuda',
        'notes'         => 'Enter your phone number. Goes to number@ml.bm',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'nbtel' => {
        'name'          => 'NBTel',
        'notes'         => 'Enter your phone number. Message is sent to number@wirefree.informe.ca',
        'fromlimit'     => 11,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'netcom' => {
        'name'          => 'Netcom',
        'notes'         => 'Enter your phone number. Goes to number@sms.netcom.no',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'nextel' => {
        'name'          => 'Nextel',
        'notes'         => '10-digit phone number. Goes to 10digits@messaging.nextel.com. Note: do not use dashes in your phone number.',
        'fromlimit'     => 50,
        'msglimit'      => 126,
        'totlimit'      => 126,
    },

    'npiwireless' => {
        'name'          => 'NPI Wireless',
        'notes'         => 'Enter your phone number. Goes to number@npiwireless.com.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'ntc' => {
        'name'          => 'NTC',
        'notes'         => 'Enter your phone number. Sent via web gateway.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },


    'o2' => {
        'name'          => 'O2 (formerly BTCellnet)',
        'notes'         => 'Enter O2 username - must be enabled first at http://www.o2.co.uk. Goes to username@o2.co.uk.',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'o2mmail' => {
        'name'          => 'O2 M-mail (formerly BTCellnet)',
        'notes'         => 'Enter phone number, omitting initial zero - must be enabled first by sending an SMS saying "ON" to phone number "212". Goes to +44[number]@mmail.co.uk.',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'optus' => {
        'name'          => 'Optus',
        'notes'         => 'Enter your phone number. Goes to @optusmobile.com.au',
        'fromlimit'     => 20,
        'msglimit'      => 114,
        'totlimit'      => 114,
    },

    'orange' => {
        'name'          => 'Orange (UK)',
        'notes'         => 'Enter your phone number. Goes to @orange.net. You will need to create a user account at orange.net first.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'oskar' => {
        'name'          => 'Oskar',
        'notes'         => 'Enter your phone number. Goes to @mujoskar.cz',
        'fromlimit'     => 20,
        'msglimit'      => 320,
        'totlimit'      => 320,
    },

    'pagenet' => {
        'name'          => 'Pagenet',
        'notes'         => '10-digit phone number (or gateway and pager number separated by a period). Goes to number@pagenet.net.',
        'fromlimit'     => 20,
        'msglimit'      => 220,
        'totlimit'      => 240,
    },

    'pcom' => {
        'name'          => 'Personal Communication (Sonet)',
        'notes'         => 'Enter your phone number. Goes to sms@pcom.ru with your number in the subject line.',
        'fromlimit'     => 20,
        'msglimit'      => 150,
        'totlimit'      => 150,
    },

    'pcsrogers' => {
        'name'          => 'PCS Rogers',
        'notes'         => '10-digit phone number. Goes to number@pcs.rogers.com. Requires prior registration with PCS Rogers.',
        'fromlimit'     => 20,
        'msglimit'      => 125,
        'totlimit'      => 125,
    },

    'phonehouse' => {
        'name'          => 'The Phone House',
        'notes'         => '10-digit phone number. Goes to number@sms.phonehouse.de.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'plusgsm' => {
        'name'          => 'Plus GSM Poland',
        'notes'         => '10-digit phone number. Goes to number@text.plusgsm.pl.',
        'fromlimit'     => 20,
        'msglimit'      => 620,
        'totlimit'      => 620,
    },

    'pscwireless' => {
        'name'          => 'PSC Wireless',
        'notes'         => 'Enter your phone number. Goes to number@sms.pscel.com',
        'fromlimit'     => 20,
        'msglimit'      => 150,
        'totlimit'      => 150,
    },


    'primtel' => {
        'name'          => 'Primtel',
        'notes'         => 'Enter your phone number. Goes to number@sms.primtel.ru',
        'fromlimit'     => 20,
        'msglimit'      => 150,
        'totlimit'      => 150,
    },

    'ptel' => {
        'name'          => 'Powertel',
        'notes'         => '10-digit phone number. Goes to number@ptel.net',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'qualcomm' => {
        'name'          => 'Qualcomm',
        'notes'         => 'Enter your username. Goes to username@pager.qualcomm.com',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'qwest' => {
        'name'          => 'Qwest',
        'notes'         => '10-digit phone number. Goes to @qwestmp.com',
        'fromlimit'     => 14,
        'msglimit'      => 100,
        'totlimit'      => 100,
    },

    'safaricom' => {
        'name'          => 'Safaricom',
        'notes'         => 'Goes to @safaricomsms.com',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'satelindogsm' => {
        'name'          => 'Satelindo GSM',
        'notes'         => 'Goes to @satelindogsm.com',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'scs900' => {
        'name'          => 'SCS-900',
        'notes'         => 'Goes to @scs-900.ru',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'simplefreedom' => {
        'name'          => 'Simple Freedom',
        'notes'         => 'Goes to @text.simplefreedom.net',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'skytelalpha' => {
        'name'          => 'Skytel - Alphanumeric',
        'notes'         => 'Enter your 7-digit pin number as your number and your message will be mailed to pin@skytel.com',
        'fromlimit'     => 15,
        'msglimit'      => 240,
        'totlimit'      => 240,
    },

    'smarttelecom' => {
        'name'          => 'Smart Telecom',
        'notes'         => 'Enter your phone number. Goes to @mysmart.mymobile.ph',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'smartsgsm' => {
        'name'          => 'Smarts GSM',
        'notes'         => 'Enter your phone number. Sent via http://www.samara-gsm.ru/scripts/smsgate.exe',
        'fromlimit'     => 11,
        'msglimit'      => 70,
        'totlimit'      => 70,
    },

    'southernlinc' => {
        'name'          => 'Southern Linc',
        'notes'         => 'Enter your 10-digit phone number. Goes to @page.southernlinc.com',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'sprintpcs' => {
        'name'          => 'Sprint PCS',
        'notes'         => 'Enter your 10-digit phone number. Goes to @messaging.sprintpcs.com',
        'fromlimit'     => 15,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'sprintpcs-shortmail' => {
        'name'          => 'Sprint PCS - Short Mail',
        'notes'         => 'Enter your phone number. Goes to @sprintpcs.com',
        'fromlimit'     => 15,
        'msglimit'      => 1000,
        'totlimit'      => 1000,
    },

    'suncom' => {
        'name'          => 'SunCom',
        'notes'         => 'Enter your number. Email will be sent to number@tms.suncom.com.',
        'fromlimit'     => 18,
        'msglimit'      => 110,
        'totlimit'      => 110,
    },

    'surewest' => {
        'name'          => 'SureWest Communications',
        'notes'         => 'Enter your phone number. Message will be sent to number@mobile.surewest.com',
        'fromlimit'     => 20,
        'msglimit'      => 200,
        'totlimit'      => 200,
    },

    'swisscom' => {
        'name'          => 'SwissCom Mobile',
        'notes'         => 'Enter your phone number. Message will be sent to number@bluewin.ch',
        'fromlimit'     => 20,
        'msglimit'      => 10000,
        'totlimit'      => 10000,
    },

    'tele2' => {
        'name'          => 'Tele2 Latvia',
        'notes'         => '10-digit phone number. Goes to number@sms.tele2.lv.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'telenor' => {
        'name'          => 'Telenor',
        'notes'         => '10-digit phone number. Goes to number@mobilpost.no.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'telia' => {
        'name'          => 'Telia Denmark',
        'notes'         => '8-digit phone number. Goes to number@gsm1800.telia.dk.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'telus' => {
        'name'          => 'Telus Mobility',
        'notes'         => '10-digit phone number. Goes to 10digits@msg.telus.com.',
        'fromlimit'     => 30,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'timnet' => {
        'name'          => 'TIM',
        'notes'         => '10-digit phone number. Goes to number@timnet.com.',
        'fromlimit'     => 30,
        'msglimit'      => 350,
        'totlimit'      => 350,
    },

    'tmobilegermany' => {
        'name'       => 'T-Mobile Germany',
        'notes'      => 'Enter your number. Email will be sent to number@T-D1-SMS.de',
        'fromlimit'  => 15,
        'msglimit'   => 160,
        'totlimit'   => 160,
    },

    'tmobileholland' => {
        'name'       => 'T-Mobile Netherlands',
        'notes'      => 'Send "EMAIL ON" to 555 from your phone, then enter your number starting with 316. Email will be sent to number@gin.nl',
        'fromlimit'  => 15,
        'msglimit'   => 160,
        'totlimit'   => 160,
    },

    'tmobileuk' => {
        'name'          => 'T-Mobile UK',
        'notes'         => 'Messages are sent to number@t-mobile.uk.net',
        'fromlimit'     => 30,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'tmobileusa' => {
        'name'          => 'T-Mobile USA',
        'notes'         => 'Messages are sent to number@tmomail.net',
        'fromlimit'     => 30,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'tmobileusasidekick' => {
        'name'          => 'T-Mobile USA (Sidekick)',
        'notes'         => 'Messages are sent to username@tmail.com',
        'fromlimit'     => 30,
        'msglimit'      => 10000,
        'totlimit'      => 10000,
    },

    'umc' => {
        'name'          => 'UMC',
        'notes'         => 'Sent by addressing the message to number@sms.umc.com.ua',
        'fromlimit'     => 10,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'uscc' => {
        'name'          => 'US Cellular',
        'notes'         => 'Enter a 10 digit USCC Phone Number. Messages are sent to number@email.uscc.net',
        'msglimit'      => 150,
        'totlimit'      => 150,
    },

    'unicel' => {
        'name'          => 'Unicel',
        'notes'         => 'Sent by addressing the message to number@utext.com',
        'fromlimit'     => 10,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'vzw' => {
        'name'          => 'Verizon Wireless',
        'notes'         => 'Enter your 10-digit phone number. Messages are sent via email to number@vtext.com.',
        'fromlimit'     => 34,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'vzw-myairmail' => {
        'name'          => 'Verizon Wireless (myairmail.com)',
        'notes'         => 'Enter your phone number. Messages are sent via to number@myairmail.com.',
        'fromlimit'     => 34,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'vessotel' => {
        'name'          => 'Vessotel',
        'notes'         => 'Enter your phone number. Messages are sent to roumer@pager.irkutsk.ru.',
        'fromlimit'     => 20,
        'msglimit'      => 800,
        'totlimit'      => 800,
    },

    'virginmobilecanada' => {
        'name'          => 'Virgin Mobile Canada',
        'notes'         => 'Enter your phone number. Messages are sent to number@vmobile.ca.',
        'fromlimit'     => 20,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'virginmobileusa' => {
        'name'          => 'Virgin Mobile USA',
        'notes'         => 'Enter your phone number. Messages are sent to number@vmobl.com.',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonees' => {
        'name'          => 'Vodafone Spain',
        'notes'         => 'Enter your username. Messages are sent to username@vodafone.es',
        'fromlimit'     => 20,
        'msglimit'      => 90,
        'totlimit'      => 90,
    },

    'vodafoneit' => {
        'name'          => 'Vodafone Italy',
        'notes'         => 'Enter your phone number. Messages are sent to number@sms.vodafone.it',
        'fromlimit'     => 20,
        'msglimit'      => 132,
        'totlimit'      => 132,
    },

    'vodafonejp-c' => {
        'name'          => 'Vodafone Japan (Toukai/Central)',
        'notes'         => 'Enter your phone number. Messages are sent to number@c.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-d' => {
        'name'          => 'Vodafone Japan (Hokkaido)',
        'notes'         => 'Enter your phone number. Messages are sent to number@d.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-h' => {
        'name'          => 'Vodafone Japan (Touhoku/Niigata/North)',
        'notes'         => 'Enter your phone number. Messages are sent to number@h.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-k' => {
        'name'          => 'Vodafone Japan (Kansai/West -- including Osaka)',
        'notes'         => 'Enter your phone number. Messages are sent to number@k.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-n' => {
        'name'          => 'Vodafone Japan (Chuugoku/Western)',
        'notes'         => 'Enter your phone number. Messages are sent to number@n.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-q' => {
        'name'          => 'Vodafone Japan (Kyuushu/Okinawa)',
        'notes'         => 'Enter your phone number. Messages are sent to number@q.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-r' => {
        'name'          => 'Vodafone Japan (Hokuriko/Central North)',
        'notes'         => 'Enter your phone number. Messages are sent to number@r.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-s' => {
        'name'          => 'Vodafone Japan (Shikoku)',
        'notes'         => 'Enter your phone number. Messages are sent to number@s.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafonejp-t' => {
        'name'          => 'Vodafone Japan (Kanto/Koushin/East -- including Tokyo)',
        'notes'         => 'Enter your phone number. Messages are sent to number@t.vodafone.ne.jp',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'vodafoneuk' => {
        'name'          => 'Vodafone UK',
        'notes'         => 'Enter your username. Messages are sent to username@vodafone.net',
        'fromlimit'     => 20,
        'msglimit'      => 70,
        'totlimit'      => 90,
    },

    'voicestream' => {
        'name'          => 'Voicestream',
        'notes'         => 'Enter your 10-digit phone number. Message is sent via the email gateway, since they changed their web gateway and we have not gotten it working with the new one yet.',
        'fromlimit'     => 15,
        'msglimit'      => 140,
        'totlimit'      => 140,
    },

    'weblinkwireless' => {
        'name'          => 'Weblink Wireless',
        'notes'         => 'Enter your phone number. Goes to @airmessage.net',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'wellcom' => {
        'name'          => 'WellCom',
        'notes'         => 'Enter your phone number. Goes to @sms.welcome2well.com',
        'fromlimit'     => 20,
        'msglimit'      => 160,
        'totlimit'      => 160,
    },

    'wyndtell' => {
        'name'          => 'WyndTell',
        'notes'         => 'Enter username/phone number. Goes to @wyndtell.com',
        'fromlimit'     => 20,
        'msglimit'      => 480,
        'totlimit'      => 500,
    },

);

sub providers
{
    my %uniq_keys = map { remap($_) => 1 } keys %providers;
    return sort { lc($providers{$a}->{'name'}) cmp lc($providers{$b}->{'name'}) } keys %uniq_keys;
}

sub provider_info
{
    my $provider = remap(shift);
    return { %{$providers{$provider}} };
}

sub remap {
    my $provider = shift;
    return "o2mmail" if $provider eq "btcellnet";
    return "voicestream" if $provider eq "voicestream2";
    return "tmobileusa" if $provider eq "tmomail";
    return "suncom" if $provider eq "tms-suncom";
    return "aliant" if $provider eq "nbtel";

    # AT&T owns a lot now
    my %att_providers = (
        'cingular' => 1,
        'cingular-acs' => 1,
        'cingular-texas' => 1,
        'cingularblue' => 1,
        'imcingular' => 1,
        'imcingular-cell' => 1,
        'pacbell' => 1,
    );
    return "att" if $att_providers{$provider};

    return $provider;
}

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;

    $self->init($args);
    return $self;
}

sub init {
    my $self = shift;
    my $args = shift;
    $self->{'provider'} = remap($args->{'provider'});
    $self->{'number'} = $args->{'number'};

    # If the number contains letters, assume provider requires
    # a username. Otherwise, strip out any parens, spaces,
    # dashes and underscores, which'll hopefully leave a
    # valid canonical telephone number.

    if ($self->{'number'} =~ /[A-Za-z@]/ ||   # if number contains letters or the @ sign
        $self->{'provider'} eq "other") {    # or if the provider is "other":
        $self->{'number'} =~ s/[\(\)\s]//g;  #     strip parens, and whitespace
    } else {                                 # else:
        $self->{'number'} =~ s/\D//g; #     strip any nonword characted, periods or hypens.
    }
}

sub send
{
    my $self = shift;
    my $msg = shift;      # hashref: 'from', 'message'
    my $errors = shift;   # arrayref
    my $provider = $self->{'provider'};

    unless ($provider) {
        push @$errors, "No provider specified in object constructor.";
        return;
    }

    unless ($msg) {
        push @$errors, "No message specified in object constructor.";
        return;
    }
    unless ($self) {
        push @$errors, "No self specified in object constructor.";
        return;
    }
    unless ($self->{'provider'}) {
        push @$errors, "No provider specified in object constructor.";
        return;
    }
    unless ($self->{'number'}) {
        push @$errors, "No number specified in object constructor.";
        return;
    }

    my $prov = $providers{$provider};

    ##
    ## truncate 'from' if it's too long for the given provider
    ##

    if (length($msg->{'from'}) > $prov->{'fromlimit'}) {
        $msg->{'from'} = substr($msg->{'from'}, 0, $prov->{'fromlimit'});
    }

    ##
    ## now send the message, based on the provider
    ##

    if ($provider eq "email")
    {
        send_mail($self, {
            'to'        => $self->{'number'},
            'from'      => $LJ::SITENAMESHORT,
            'body'      => "(f:$msg->{'from'})$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "airtouch")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sender.airtouchpaging.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "aliant")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@chat.wirefree.ca",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "alltel")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@message.alltel.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "ameritech")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@paging.acswireless.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "arch")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@archwireless.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "att")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@txt.att.net",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "aubykddi")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@ezweb.ne.jp",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "beemail")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.beemail.ru",
            'body'      => "$msg->{'from'} - $msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "bellmobilityca")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@txt.bellmobility.ca",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "bellsouth")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@bellsouth.cl",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "bellsouthmobility")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@blsdcs.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }


    elsif ($provider eq "blueskyfrog")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@blueskyfrog.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "boost")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@myboostmobile.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "cellularonedobson")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@mobile.celloneusa.com",
            'from'      => "$msg->{'from'}",
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "cellularonewest")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@mycellone.net",
            'from'      => "$msg->{'from'}",
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "centennial")
    {
        post_webform("http://www.centennialwireless.com/sms/sms.php", {
            'deviceid'   => $self->{'number'},
            'mess'       => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "cincinnatibell")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@gocbw.com",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "claro")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@clarotorpedo.com.br",
            'from'      => "$msg->{'from'}",
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "comviq") {
        send_mail($self, {
            'to' => "$self->{'number'}\@sms.comviq.se",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "csouth1") {
        send_mail($self, {
            'to' => "$self->{'number'}\@csouth1.com",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "dutchtone")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.orange.nl",
            'body'      => "$msg->{'from'}\n$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "edgewireless") {
        send_mail($self, {
            'to' => "$self->{'number'}\@sms.edgewireless.com",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

   elsif ($provider eq "einstein") {
        send_mail($self, {
            'to' => "$self->{'number'}\@einsteinsms.com",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "emt")
    {
        post_webform("http://www.emt.ee/wwwmain", {
            'actionId'   => "send",
            'phoneNo'    => $self->{'number'},
            'userEmail'  => $msg->{'from'},
            'message'    => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "eplus")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@smsmail.eplus.de",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "fidoca" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@fido.ca",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "goldentelecom") {
        send_mail($self, {
            'to' => "$self->{'number'}\@sms.goldentele.com",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "ideacellular") {
        send_mail($self, {
            'to' => "$self->{'number'}\@ideacellular.net",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "kyivstar")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.kyivstar.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "lmt")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.lmt.lv",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "meteor")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.mymeteor.ie",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "metrocall")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@page.metrocall.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "metropcs")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@mymetropcs.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "mobileone")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@m1.com.sg",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "mobilfone")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@page.mobilfone.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "movistar")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@movistar.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "mtsmobility")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@text.mtsmobility.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "mtsprimtel")
    {
        post_webform("http://80.83.224.19/sms/sent_sakh.shtml", {
            'ref'       => 8,
            'txtAddr'  => $self->{'number'},
            'textSM'     => "(f:".$msg->{'from'}.")".$msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "mobility")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@ml.bm",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "nbtel")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@wirefree.informe.ca",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "netcom")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.netcom.no",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "nextel")  # Nextel
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@messaging.nextel.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "npiwireless")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@npiwireless.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "ntc")
    {
        my $prefix;
        my $number;
        if ($self->{'number'} =~ /^74232(\d\d\d\d\d\d)/) {
            $prefix = "74232";
            $number = $1;
        }
        if ($self->{'number'} =~ /^(7902\d\d\d)(\d\d\d\d)/) {
            $prefix = $1;
            $number = $2;
        }
        post_webform("http://www.ntconline.ru/data/pages/sms/send.php", {
            'sent'      => 1,
            'prefix'    => $prefix,
            'number'    => $number,
            'lang'      => "eng",
            'body'       => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "ntelos")  # NTELOS PCS
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@pcs.ntelos.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "o2")
    {
        send_mail($self, {
            'to'        => $self->{'number'}."\@o2.co.uk",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "o2mmail")
    {
        send_mail($self, {
            'to'        => "+44".$self->{'number'}."\@mmail.co.uk",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "optus")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@optusmobile.com.au",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "orange")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@orange.net",
            'from'      => "$msg->{'from'}",
            'subject'   => "$msg->{'message'}",
            'body'      => "Textmessage in subject line.",
        },$errors);
    }

    elsif ($provider eq "oskar")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@musoskar.cz",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "pagenet")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@pagenet.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "pcom")
    {
        send_mail($self, {
            'to'        => "sms\@pcom.ru",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => "$self->{'number'}",
        },$errors);
    }

    elsif ($provider eq "pcsrogers")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@pcs.rogers.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
         },$errors);
    }

    elsif ($provider eq "phonehouse")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.phonehouse.de",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "plusgsm")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@text.plusgsm.pl",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "pscwireless")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.pscel.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "primtel")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.primtel.ru",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "ptel")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@ptel.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

   elsif ($provider eq "qualcomm")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@pager.qualcomm.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "qwest")
    {
        send_mail($self, {
            'to'        => "(f:$msg->{'from'})$self->{'number'}\@qwestmp.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "safaricom")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@safaricomsms.com",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "satelindogsm")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@satelindogsm.com",
            'from'      => $LJ::BOGUS_EMAIL,
            'body'      => "From: $msg->{'from'}\n$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "scs900")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@scs-900.ru",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "simplefreedom")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@text.simplefreedom.net",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "skytelalpha")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@skytel.com",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "smarttelecom") {
        send_mail($self, {
            'to'   => "$self->{'number'}\@mysmart.mymobile.ph",
            'from' => "$msg->{'from'}",
            'body' => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "smartsgsm")
    {
        post_webform("http://www.samara-gsm.ru/scripts/smsgate.exe/send", {
            "phone"     => $self->{'number'},
            "sendtext"  => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "southernlinc")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@page.southernlinc.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "sprintpcs") # SprintPCS
    {
        send_mail($self, {
            'to'        => "(f:$msg->{'from'}) $self->{'number'}\@messaging.sprintpcs.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "sprintpcs-shortmail")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sprintpcs.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "suncom") {
        send_mail($self, {
            'to'   => "$self->{'number'}\@tms.suncom.com",
            'from' => "$msg->{'from'}",
            'body' => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "surewest") {
        send_mail($self, {
            'to'   => "$self->{'number'}\@mobile.surewest.com",
            'body' => "(f:$msg->{'from'}) $msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "swisscom") {
        send_mail($self, {
            'to'   => "$self->{'number'}\@bluewin.ch",
            'from' => "$msg->{'from'}",
            'body' => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "tele2") {
        post_webform("http://sms.tele2.lv/cgi-bin/send_sm_t2.cgi", {
            "msisdn"    => $self->{'number'},
            "text"      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "telenor") {
        send_mail($self, {
            'to'        => "$self->{'number'}\@mobilpost.no",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "telia") {
        send_mail($self, {
            'to'        => "$self->{'number'}\@gsm1800.telia.dk",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "telus")  # Telus Mobility
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@msg.telus.com",
            'from'      => "$msg->{'from'}",
            'body'      => "(f:$msg->{'from'})$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "timnet")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@timnet.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "tmobileaustria")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.t-mobile.at",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "tmobilegermany")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@T-D1-SMS.de",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "tmobileholland")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@gin.nl",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "tmobileuk")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@t-mobile.uk.net",
            'subject'   => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'from'      => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "tmobileusa")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@tmomail.net",
            'subject'   => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'from'      => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "tmobileusasidekick")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@tmail.com",
            'subject'   => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'from'      => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "umc")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.umc.com.ua",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "uscc")  # U.S Cellular
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@email.uscc.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
         },$errors);
    }

    elsif ($provider eq "unicel")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@utext.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "vzw")  # Verizon Wireless
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@vtext.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => $LJ::SITENAMEABBREV,
        },$errors);
    }

    elsif ($provider eq "vzw-myairmail")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@myairmail.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "vessotel" )
    {
        send_mail($self, {
            'to'        => "roumer\@pager.irkutsk.ru",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'   => "$self->{'number'}",
        },$errors);
    }

    elsif ($provider eq "virginmobilecanada" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@vmobile.ca",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "virginmobileusa" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@vmobl.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "vodafonees") {
        send_mail($self, {
            'to' => "$self->{'number'}\@vodafone.es",
            'from' => $msg->{'from'},
            'subject' => $msg->{'message'},
            'body' => "Your $LJ::SITENAMESHORT Text Message has been placed into the subject line."
        },$errors);
    }

    elsif ($provider eq "vodafoneit") {
        send_mail($self, {
            'to' => "$self->{'number'}\@sms.vodafone.it",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-c") {
        send_mail($self, {
            'to' => "$self->{'number'}\@c.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-d") {
        send_mail($self, {
            'to' => "$self->{'number'}\@d.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-h") {
        send_mail($self, {
            'to' => "$self->{'number'}\@h.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-k") {
        send_mail($self, {
            'to' => "$self->{'number'}\@k.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-n") {
        send_mail($self, {
            'to' => "$self->{'number'}\@n.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-q") {
        send_mail($self, {
            'to' => "$self->{'number'}\@q.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-r") {
        send_mail($self, {
            'to' => "$self->{'number'}\@r.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-s") {
        send_mail($self, {
            'to' => "$self->{'number'}\@s.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafonejp-t") {
        send_mail($self, {
            'to' => "$self->{'number'}\@t.vodafone.ne.jp",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "vodafoneuk") {
        send_mail($self, {
            'to' => "$self->{'number'}\@vodafone.net",
            'from' => $msg->{'from'},
            'subject' => $msg->{'message'},
            'body' => "Your $LJ::SITENAMESHORT Text Message has been placed into the subject line."
        },$errors);
    }

    elsif ($provider eq "voicestream" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@voicestream.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        },$errors);
    }

    elsif ($provider eq "weblinkwireless")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@airmessage.net",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "wellcom")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.welcome2well.com",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    elsif ($provider eq "wyndtell")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@wyndtell.com",
            'from'      => $msg->{'from'},
            'body'      => $msg->{'message'},
        },$errors);
    }

    else {
        push @$errors, "Tried to send a message to an unknown or unsupported provider.";
    }
}

sub post_webform
{
    my ($url, $postvars, $errors) = @_;

    ### we're going to POST to provider's page
    my $ua = LJ::get_useragent(role => 'textmessage');
    $ua->agent("Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)");
    $ua->timeout(5);

    my $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content(request_string($postvars));

    # Pass request to the user agent and get a response back
    my $res = $ua->request($req);
    if ($res->is_success || $res->is_redirect) {
        return;
    } else {
        push @$errors, "There was some error contacting the user's text messaging service via its web gateway. The message was most likely not sent.";
        return;
    }
}

sub send_mail {
    my ($self, $opt, $errors) = @_;

    unless ($opt->{'to'}) {
        push @$errors, "To not defined in provider description.";
        return;
    }
    unless ($opt->{'body'}) {
        push @$errors, "Data not defined in provider description.";
        return;
    }
    $opt->{'from'} =~ s,[!\\/\@#],_,g; # I haven't escaped too much/too little, have I?
    my $msg =  MIME::Lite->new('From' => $opt->{'from'} . "\@$LJ::DOMAIN",
                               'To' => $opt->{'to'},
                               'Subject' => $opt->{'subject'},
                               'Data' => $opt->{'body'});

    return LJ::send_mail($msg);
}

sub request_string
{
    my ($vars) = shift;
    my $req = "";
    foreach (sort keys %{$vars})
    {
        my $val = uri_escape($vars->{$_},"\+\=\&");
        $val =~ s/ /+/g;
        $req .= "&" if $req;
        $req .= "$_=$val";
    }
    return $req;
}

# get the textmessage info for a user
# if 'remap_result' opt is passed in, then it will perform the remap on the provider name before returning
sub tm_info {
    my ($self, $u, %opts) = @_;
    my $dbr = LJ::get_db_reader();
    my $result = $dbr->selectrow_hashref("SELECT * ".
                                         "FROM txtmsg WHERE userid=?", undef, $u->{'userid'});

    if ($opts{remap_result}) {
        $result->{provider} = remap($result->{provider});
    }

    return $result;
}

# get only the text message security level that the user has set
# possible values: all, friends, reg, none
sub tm_security {
    my ($self, $u) = @_;

    my $userid = $u->id;
    my $security;

    $security = $u->{_txtmsgsecurity};
    return $security if $security;

    my $memkey = [$userid, "txtmsgsecurity:$userid"];
    $security = LJ::MemCache::get($memkey);
    if ($security) {
        $u->{_txtmsgsecurity} = $security;
        return $security;
    }

    $security = "none" if $u->{txtmsg_status} eq "off" || $u->{txtmsg_status} eq "none";
    unless ($security) {
        my $tminfo = LJ::TextMessage->tm_info($u);
        $security = $tminfo && $tminfo->{security} ? $tminfo->{security} : "none";
    }
    $u->{_txtmsgsecurity} = $security;
    LJ::MemCache::set($memkey, $security, 60*5);

    return $security;
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

LJ::TextMessage - text message phones/pages using a variety of methods/services

=head1 SYNOPSIS

  use LJ::TextMessage;

  @providers = LJ::TextMessage::providers();
  foreach my $p (@providers) {
      my $info = LJ::TextMessage::provider_info($p);
      print "Name: $info->{'name'}\n";
      print "Notes: $info->{'notes'}\n";
      print "Limits: \n";
      foreach my $limit (qw(from msg tot)) {
          print "  $limit: ", $info->{"${limit}limit"}, "\n";
      }
  }

  my $phone = new LJ::TextMessage {
      'provider' => 'voicestream',
      'number' => '2045551212',
  };

  my @errors;
  $phone->send({ 'from' => 'Bob',
                 'message' => "Hello!  This is my message!" },
               \@errors);
  if (@errors) {
      ...
  } else {
      print "Message sent!\n";
  }

=head1 DESCRIPTION

The synopsis pretty much shows all the functionality that's available,
but details would be nice here.

=head1 BUGS

This library is highly volatile, as cellphone and pager providers can
change the details of their web or email gateways at any time. In
practice I haven't had to update this library much, but providers have
no responsibility to tell me when they change their form field names
on their website, or change URLs*.

This documentation sucks rancid goats**.


*  - This will, of course, change once LJ has conquered the world.
** - No, not Frank.

=head1 AUTHOR

Current maintainers:
  - Aaron B. Russell (idigital) - <idigital@livejournal.com>
  - Eric Carr (iicarrii) - <iicarrii@aol.com>

Based on (mostly still, actually) code by:
  - Brad Fitzpatrick (bradfitz) - <bradfitz@bradfitz.com>
  - Nicholas Tang (ntang) - <ntang@livejournal.com>

Additional code provided by:
  - Larry Gilbert (l2g) - <l2g@livejournal.com>
  - (delphy)
  - (rory)
  - Tony Sutton (tsutton) - <tsutton@livejournal.com>
  - Chris Bartow (christowang) - <chris@sysice.com>
  - Gavin Mogan (halkeye) - <halkeye@livejournal.com>
  - Steven Kreuzer (22dip) - <skreuzer@mac.com>
(if you've been forgotten, please give a holler!)

Information about text messaging gateways from many.

=cut
