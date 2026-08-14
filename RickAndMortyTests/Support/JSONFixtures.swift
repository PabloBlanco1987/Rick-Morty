import Foundation

// Payloads copiados tal cual de rickandmortyapi.com.
// Los guardo como literales y no como .json en el bundle para no montar nada de
// recursos y para que ningún test pase en falso porque un fichero no se copió.
enum JSONFixtures {
    static let rick = #"""
    {
      "id": 1,
      "name": "Rick Sanchez",
      "status": "Alive",
      "species": "Human",
      "type": "",
      "gender": "Male",
      "origin": { "name": "Earth (C-137)", "url": "https://rickandmortyapi.com/api/location/1" },
      "location": { "name": "Citadel of Ricks", "url": "https://rickandmortyapi.com/api/location/3" },
      "image": "https://rickandmortyapi.com/api/character/avatar/1.jpeg",
      "episode": [
        "https://rickandmortyapi.com/api/episode/1",
        "https://rickandmortyapi.com/api/episode/2"
      ],
      "url": "https://rickandmortyapi.com/api/character/1",
      "created": "2017-11-04T18:48:46.250Z"
    }
    """#

    // Pasa por todos los caminos de degradación del mapper a la vez: un status y un
    // gender que el enum no conoce, una imagen que no es URL y enlaces de episodio
    // que no acaban en un id.
    static let malformedCharacter = #"""
    {
      "id": 999,
      "name": "Glitch",
      "status": "Schrodinger",
      "species": "Anomaly",
      "type": "Superposition",
      "gender": "Yes",
      "origin": { "name": "unknown", "url": "" },
      "location": { "name": "unknown", "url": "" },
      "image": "",
      "episode": [
        "https://rickandmortyapi.com/api/episode/7",
        "https://rickandmortyapi.com/api/episode/not-a-number"
      ],
      "url": "https://rickandmortyapi.com/api/character/999",
      "created": "2017-11-04T18:48:46.250Z"
    }
    """#

    static let charactersPage = #"""
    {
      "info": { "count": 826, "pages": 42, "next": "https://rickandmortyapi.com/api/character?page=2", "prev": null },
      "results": [
        {
          "id": 1, "name": "Rick Sanchez", "status": "Alive", "species": "Human", "type": "", "gender": "Male",
          "origin": { "name": "Earth (C-137)", "url": "" },
          "location": { "name": "Citadel of Ricks", "url": "" },
          "image": "https://rickandmortyapi.com/api/character/avatar/1.jpeg",
          "episode": ["https://rickandmortyapi.com/api/episode/1"],
          "url": "", "created": "2017-11-04T18:48:46.250Z"
        },
        {
          "id": 2, "name": "Morty Smith", "status": "Alive", "species": "Human", "type": "", "gender": "Male",
          "origin": { "name": "unknown", "url": "" },
          "location": { "name": "Citadel of Ricks", "url": "" },
          "image": "https://rickandmortyapi.com/api/character/avatar/2.jpeg",
          "episode": ["https://rickandmortyapi.com/api/episode/1"],
          "url": "", "created": "2017-11-04T18:50:21.651Z"
        }
      ]
    }
    """#

    // Lo que contesta de verdad /character/?name=zzzz: un 404 con este cuerpo, no un
    // results vacío
    static let notFoundError = #"""
    { "error": "There is nothing here" }
    """#

    // /episode/1, un objeto suelto
    static let singleEpisode = #"""
    {
      "id": 1,
      "name": "Pilot",
      "air_date": "December 2, 2013",
      "episode": "S01E01",
      "characters": ["https://rickandmortyapi.com/api/character/1"],
      "url": "https://rickandmortyapi.com/api/episode/1",
      "created": "2017-11-10T12:56:33.798Z"
    }
    """#

    // /episode/1,2, un array. Mismo endpoint, otra forma
    static let episodeArray = #"""
    [
      {
        "id": 1, "name": "Pilot", "air_date": "December 2, 2013", "episode": "S01E01",
        "characters": [], "url": "", "created": "2017-11-10T12:56:33.798Z"
      },
      {
        "id": 2, "name": "Lawnmower Dog", "air_date": "December 9, 2013", "episode": "S01E02",
        "characters": [], "url": "", "created": "2017-11-10T12:56:33.916Z"
      }
    ]
    """#

    static let malformedEpisode = #"""
    {
      "id": 3,
      "name": "Anatomy Park",
      "air_date": "sometime in the winter",
      "episode": "S01E03"
    }
    """#
}
