def xbox_downloads:
  ["domain:assets1.xboxlive.com", "domain:assets2.xboxlive.com",
   "domain:dlassets.xboxlive.com", "domain:dlassets2.xboxlive.com",
   "domain:d1.xboxlive.com", "domain:d2.xboxlive.com",
   "domain:dlassets-ssl.xboxlive.com", "domain:xvcf1.xboxlive.com",
   "domain:xvcf2.xboxlive.com", "domain:delivery.mp.microsoft.com",
   "domain:dl.delivery.mp.microsoft.com"];
def xbox_services:
  ["domain:login.live.com", "domain:account.live.com",
   "domain:accounts.xboxlive.com", "domain:device.auth.xboxlive.com",
   "domain:user.auth.xboxlive.com", "domain:xsts.auth.xboxlive.com",
   "domain:title.auth.xboxlive.com", "domain:xboxlive.com",
   "domain:xboxservices.com", "domain:xboxab.com"];
def scoped_rule($out; $domains):
  {type:"field", inboundTag:["redirect","tproxy"], source:$sources,
   outboundTag:$out, domain:$domains};

if ([.routing.rules[] | select((.source // []) == $sources and
     ((.domain // []) | index("domain:login.live.com")) != null)] | length) != 0
then error("Xbox scoped rules already exist")
else . end
| .routing.rules |= (
    . as $rules
    | [to_entries[] | select((.value.domain // []) | index("domain:xbox.com")) | .key] as $anchors
    | if ($anchors | length) != 1 then error("Xbox anchor missing or ambiguous")
      else $anchors[0] as $i
      | $rules[:$i] + [scoped_rule("direct"; xbox_downloads),
                       scoped_rule("vless-reality-test"; xbox_services)] + $rules[$i:]
      end)
