<!DOCTYPE html>
<html>

<head>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-core.js" type="text/javascript" charset="utf-8"></script>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-service.js" type="text/javascript" charset="utf-8"></script>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-ui.js" type="text/javascript" charset="utf-8"></script>
  <script src="https://js.api.here.com/v3/3.1/mapsjs-mapevents.js" type="text/javascript" ></script>

  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
  <script src="https://code.jquery.com/ui/1.12.1/jquery-ui.js"></script>
  
  <script src='https://unpkg.com/@turf/turf/turf.min.js'></script>
 
   
  <link rel="stylesheet" href="https://code.jquery.com/ui/1.12.1/themes/base/jquery-ui.css">
  
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
  <div id="input">
    <input type="range" id="slider" min="1" max="3600" value="1800" />
    <input type="button" id="okButton" value="OK" onclick="submit()" />
  </div>
  <div id="report"></div>

  <script>
    const initialCoords = '48.13,11.58'
    var map;
    var router;
      
    async function initMap() {
      var platform = new H.service.Platform({ 'apikey': myApiKey });
      router = platform.getRoutingService();
      var defaultLayers = platform.createDefaultLayers();

      // add the map and set the initial center to Munich
      map = new H.Map(
        document.getElementById('map'),
        defaultLayers.vector.normal.map,
        {
          zoom: 10,
          center: { lat: 48.13, lng: 11.58 }
        });
      var ui = H.ui.UI.createDefault(map, defaultLayers, 'de-DE');
      var behavior = new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
    }

    createInputElements(0);
    initMap();
    
    function getCenterPoint(response) {
      return new H.geo.Point(
        response.response.center.latitude,
        response.response.center.longitude
      );
    };
    
    function getIsolinePolygon(result) {
        var isolineCoords = result.response.isoline[0].component[0].shape;
        var linestring = new H.geo.LineString();

        // Add the returned isoline coordinates to a linestring:
        isolineCoords.forEach(coords => {
          linestring.pushLatLngAlt.apply(linestring, coords.split(','));
        });
     
        return new H.geo.Polygon(linestring);
    };

    function getReachableDestinations(response, destinations, maxTravelTime) {
      var reachableDestinations = destinations.map((x, i) => {
        var coords = x.split(',');
        return {
          index: i,
          lat: coords[1], // coords are swapped by calculateMatrix
          lng: coords[0],
          reachable: true
        }
      });

      for(var x of Object.values(response.response.matrixEntry)) {
        var d = reachableDestinations[x.destinationIndex];
        
        d.reachable = d.reachable && x.summary && x.summary.costFactor <= maxTravelTime;
      }
      return reachableDestinations;
    };

    function createInputElements(index) {
      $("#okButton").before(`
        <div id="input${ index }">
          <input type="text" onkeyup="suggestLocationsAsync(event)" id="locationTextbox${ index }"/>
          <input type="button" value="+" onclick="createInputElements(${ index + 1 })" />
          <input type="button" value="-" onclick="removeInputElements(${ index })" />
        </div>`);
    };
    function removeInputElements(index) {
      $(`#input${ index }`).remove();
    }
    
    async function suggestLocationsAsync(event) {
      var target = event.target;
      var text = target.value;
      if(text.length > 5) {
        var locations = await getSuggestionsAsync(event, text);
        var suggestions = locations.items.map(x => x.title);
        $(target).autocomplete({ source: suggestions });
      }
    };

    function getSuggestionsAsync(event, searchString) {
      return new Promise(function(resolve, reject) {
        $.ajax({
          url: 'https://geocode.search.hereapi.com/v1/autosuggest',
          type:'GET',
          dataType: 'json',
          data: {
            apikey: myApiKey, 
            q: searchString,
            limit: 5,
            lang: 'de-DE',
            at: initialCoords
          },
          success: result => resolve(result)
        });
      });
    };   
  
    function submit() {
      var locations = $("input[type=text]").map(function() { return $(this).val(); });
      maxTravelTime = $("#slider").val();
      perform(locations);
    };

    async function perform(sourceLocations) {
      var featureCollection = await queryFeaturesFromDataHubAsync();
      await calculateReachabilityAsync(featureCollection.features, sourceLocations)
    };

    function calculateIsolineAsync(routingParams, features) {
      return new Promise(function(resolve, reject) {
        // Call the Routing API to calculate an isoline:
        router.calculateIsoline(
          routingParams,
          isolineResponse => {
            var centerPoint = getCenterPoint(isolineResponse);
            var isolinePolygon = getIsolinePolygon(isolineResponse);
            resolve(isolinePolygon);            
          },
          error => { reject(error.message); }
        );
      });
    }
    
    function calculateReachabilityMatrixAsync(postData) {
      return new Promise(function(resolve, reject) {
        $.ajax({
          url: 'https://matrix.route.ls.hereapi.com/routing/7.2/calculatematrix.json',
          type: 'POST',
          dataType: 'jsonp',
          jsonp: 'jsoncallback',
          data: postData,
          success: result => resolve(result) 
        });
      });
    }
    
    function geocodeAsync(location) {
      return new Promise(function(resolve, reject) {
        $.ajax({
          url: 'https://geocode.search.hereapi.com/v1/geocode',
          type:'GET',
          dataType: 'json',
          async: false,
          data: {
            apikey: myApiKey, 
            q: location
          },
          success: result => resolve(result)
        });
      });
    }
  
    async function calculateReachabilityAsync(features, sourceLocations) {
      const intersectingObjects = [];
          
      // perform an m:n-routing
      var destinations = features.map(x => x.geometry.coordinates.join());
      var postData = { 
        mode: 'fastest;car;traffic:disabled',
        summaryAttributes: 'traveltime',
        apiKey: myApiKey
      }
      for(var i = 0; i < destinations.length; i++) {
        var coords = destinations[i].split(',');
        // swap the coords, we need LatLng, but we get LngLat from data-hub
        postData[`destination${i}`] = `${coords[1]},${coords[0]}`;
      }
      for(var i = 0; i < sourceLocations.length; i++) {
        var location = await geocodeAsync(sourceLocations[i]);       
        var coords = location.items[0].position;
        var latLng = `${ coords.lat },${ coords.lng }`;
        postData[`start${ i }`] = latLng;

        var routingParams = {
          mode: 'fastest;car;traffic:disabled',
          start: `geo!${ latLng }`,
          range: `${ maxTravelTime },${ maxTravelTime * 2 }`,
          rangetype: 'time'
        };                   
        let isolinePolygon = await calculateIsolineAsync(routingParams, features);
        map.addObject(new H.map.Polygon(isolinePolygon));
      }

      var matrix = await calculateReachabilityMatrixAsync(postData);
      for(const item of getReachableDestinations(matrix, destinations, maxTravelTime))
      {
        var color = item.reachable ? 'green' : 'red';
          var svg = 
            `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
              <circle cx="5" cy="5" r="5" fill="${ color }" />
            </svg>`;
          map.addObject(new H.map.Marker({ lat: item.lat, lng: item.lng }, { icon: new H.map.Icon(svg)}));
      }
    }
  </script>
</body>

</html>