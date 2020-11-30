<!DOCTYPE html>
<html>

<head>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-core.js" type="text/javascript" charset="utf-8"></script>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-service.js" type="text/javascript" charset="utf-8"></script>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-ui.js" type="text/javascript" charset="utf-8"></script>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-mapevents.js" type="text/javascript" ></script>
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
  <script src='https://unpkg.com/@turf/turf/turf.min.js'></script>
  
  <link rel="stylesheet" type="text/css" href="https://js.api.here.com/v3/3.1/mapsjs-ui.css" />
  <style>
    html,
    body {
      width: 100%;
      height: 100%;
      margin: 0;
    }

    #map {
      width: 80%;
      height: 100%;
      float: left;
    }
    #report {
      height: 100%;
    }
  </style>
</head>

<body>
  <!--  where the map will live  -->
  <div id="map"></div>
  <div>
    <input id="" type="input" /><input value="+" type="button" onclick=""/><input value="-" type="button" onclick=""/>
    <br />
    <input value="OK" type="button" onclick="" />
  </div>
  <div id="report"></div>

  <script>
    async function initMap() {
      var maxTravelTime = 1800;

      var platform = new H.service.Platform({ 'apikey': myApiKey });
      var defaultLayers = platform.createDefaultLayers();

      // add the map and set the initial center to berlin
      var map = new H.Map(
        document.getElementById('map'),
        defaultLayers.vector.normal.map,
        {
          zoom: 10,
          center: { lat: 48.13, lng: 11.58 }
        });
      var ui = H.ui.UI.createDefault(map, defaultLayers, 'de-DE');
      var behavior = new H.mapevents.Behavior(new H.mapevents.MapEvents(map));

      var routingParams = {
        'mode': 'fastest;car;',
        'start': 'geo!48.13,11.58',
        'range': '150,300',
        'rangetype': 'time'
      };

      // Get an instance of the routing service:
      var router = platform.getRoutingService();

      /* the following for whatever reason transforms the POST to get which server isn´t able to handle
      $.post({
            url: 'https://xyz.api.here.com/hub/spaces/CgQGUsrk/spatial?p.qualityLevel=4',
            dataType: 'json',
            data: {
                type: "Point",
                coordinates: [52.4990273,13.3881283],
                apiKey: myApiKey
                accessToken: accessToken
             }
          });
      */
     
     
      const intersectingObjects = [];
      // request all POIs
      const response = await fetch('munich-places-v90_CgQGUsrk.geojson')
        .then(x => x.json())
        .then(featureCollection => {
          // Call the Routing API to calculate an isoline:
          router.calculateIsoline(
            routingParams,
            function(result) {
              var centerPoint = getCenterPoint(result);
              var isolinePolygon = getIsolinePolygon(result);
              
              // Add the polygon and marker to the map:
              map.addObjects([
                new H.map.Marker(centerPoint), 
                new H.map.Polygon(isolinePolygon)
              ]);

              // Center and zoom the map so that the whole isoline polygon is
              // in the viewport:
              map.getViewModel().setLookAtData({bounds: isolinePolygon.getBoundingBox()});
            
              var geoJSON = isolinePolygon.toGeoJSON()
              for(var f of Object.values(featureCollection.features)) {
                if(turf.intersect(f, geoJSON))
                  intersectingObjects.push(f);
              }
            },
            function(error) {
              alert(error.message);
            }
          );

          // perform an m:n-routing
          var destinations = featureCollection.features.map(x => x.geometry.coordinates.join());
          var postData = { 
            start0: '52.5139,13.3576',
            mode: 'fastest;car',
            summaryAttributes: 'traveltime',
            apiKey: myApiKey
          }
          for(var i = 0; i < 100 /*destinations.length*/; i++)
          {
            var coords = destinations[i].split(',');
            // swap the coords, we need LatLng, but we get LngLat from the geoJSON
            postData[`destination${i}`] = `${coords[1]},${coords[0]}`;
          }
          $.ajax({
            url: 'https://matrix.route.ls.hereapi.com/routing/7.2/calculatematrix.json',
            type: 'POST',
            dataType: 'jsonp',
            jsonp: 'jsoncallback',
            data: postData,
            success: function (response) {
              for(const item of getReachableDestinations(response, destinations, maxTravelTime))
                map.addObject(new H.map.Marker({ lat: item.lat, lng: item.lng }));
            }
          });

        });       
    }

    initMap();

    function getCenterPoint(response) {
      return new H.geo.Point(
        response.response.center.latitude,
        response.response.center.longitude
      );
    }
    
    function getIsolinePolygon(result) {
        var isolineCoords = result.response.isoline[0].component[0].shape;
        var linestring = new H.geo.LineString();

        // Add the returned isoline coordinates to a linestring:
        isolineCoords.forEach(coords => {
          linestring.pushLatLngAlt.apply(linestring, coords.split(','));
        });
     
        return new H.geo.Polygon(linestring);
    };

    function* getReachableDestinations(response, destinations, maxTravelTime) {
      var reachableDestinations = destinations.map((x, i) => {
        var coords = x.split(',');
        return {
          index: i,
          lat: coords[1], // coords are swapped by calculateMatrix
          lng: coords[0],
          reachability: true
        }
      });

      for(var x of Object.values(response.response.matrixEntry)) {
        var d = reachableDestinations[x.destinationIndex];
        if(d.reachability === false)
          continue;

        d.reachability = x.summary.costFactor <= maxTravelTime;
        yield d;
      }
    }

  </script>
</body>

</html>