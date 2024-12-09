// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GestionnaireRisqueContrepartie {
    struct Contrepartie {
        address portefeuille;
        uint256 scoreCredit;
        uint256 limiteExposition;
        uint256 expositionCourante;
        uint256 collateral;
        bool estActif;
        uint256 probabiliteDefaut;
        uint256 pertesEnCasDefaut;
    }

    // Variables d'état
    mapping(address => Contrepartie) public contreparties;
    mapping(address => uint256[]) public historiqueExpositions;
    address[] private toutesLesAdresses; // Liste des adresses des contreparties
    address public administrateur;

    // Événements
    event ContrepartieAjoutee(address indexed contrepartie, uint256 limiteExposition);
    event ExpositionMiseAJour(address indexed contrepartie, uint256 nouvelleExposition);
    event ContrepartieDesactivee(address indexed contrepartie);
    event ContrepartieActivee(address indexed contrepartie);
    event ExpositionLimiteDepassee(address indexed contrepartie, uint256 expositionCourante);
    event Alerte85PourcentLimite(address indexed contrepartie, uint256 expositionCourante);
    event StatistiquesGlobales(uint256 totalContrepartiesActives, uint256 expositionTotale, uint256 tauxMoyenCouverture);

    // Modificateurs
    modifier seulementAdministrateur() {
        require(msg.sender == administrateur, unicode"Seul l'administrateur peut exécuter cette action.");
        _;
    }

    // Constructeur
    constructor() {
        administrateur = msg.sender;
    }

    // Ajouter une contrepartie
    function ajouterContrepartie(
        address _portefeuille,
        uint256 _scoreCredit,
        uint256 _limiteExposition,
        uint256 _collateral,
        uint256 _probabiliteDefaut,
        uint256 _pertesEnCasDefaut
    ) public seulementAdministrateur {
        require(_portefeuille != address(0), unicode"Adresse invalide.");
        require(!contreparties[_portefeuille].estActif, unicode"La contrepartie existe déjà.");
        require(_scoreCredit > 0 && _scoreCredit <= 100, unicode"Le score de crédit doit être entre 1 et 100.");
        require(_limiteExposition > 0, unicode"La limite d'exposition doit être supérieure à 0.");
        require(_probabiliteDefaut >= 0 && _probabiliteDefaut <= 100, unicode"La probabilité de défaut doit être entre 0 et 100.");
        require(_pertesEnCasDefaut >= 0 && _pertesEnCasDefaut <= 100, unicode"Les pertes en cas de défaut doivent être entre 0 et 100.");

        contreparties[_portefeuille] = Contrepartie({
            portefeuille: _portefeuille,
            scoreCredit: _scoreCredit,
            limiteExposition: _limiteExposition,
            expositionCourante: 0,
            collateral: _collateral,
            estActif: true,
            probabiliteDefaut: _probabiliteDefaut,
            pertesEnCasDefaut: _pertesEnCasDefaut
        });
        toutesLesAdresses.push(_portefeuille);
        emit ContrepartieAjoutee(_portefeuille, _limiteExposition);
    }

    // Mettre à jour l'exposition
    function mettreAJourExposition(address _portefeuille, uint256 _nouvelleExposition) public seulementAdministrateur {
        require(contreparties[_portefeuille].estActif, unicode"Contrepartie désactivée.");
        Contrepartie storage c = contreparties[_portefeuille];
        c.expositionCourante = _nouvelleExposition;
        historiqueExpositions[_portefeuille].push(_nouvelleExposition);

        if (c.expositionCourante >= c.limiteExposition * 85 / 100 && c.expositionCourante < c.limiteExposition) {
            emit Alerte85PourcentLimite(_portefeuille, _nouvelleExposition);
        }
        if (c.expositionCourante >= c.limiteExposition) {
            emit ExpositionLimiteDepassee(_portefeuille, _nouvelleExposition);
        }
        emit ExpositionMiseAJour(_portefeuille, _nouvelleExposition);
    }

    // Désactiver une contrepartie
    function desactiverContrepartie(address _portefeuille) public seulementAdministrateur {
        Contrepartie storage c = contreparties[_portefeuille];
        require(c.estActif, unicode"Contrepartie déjà désactivée.");
        require(c.scoreCredit < 50, unicode"Score de crédit insuffisant.");
        require(calculerScoreDeRisque(_portefeuille) > 70, unicode"Score de risque insuffisant.");

        c.estActif = false;
        emit ContrepartieDesactivee(_portefeuille);
    }

    // Calcul des pertes attendues
    function calculerPertesAttendues(address _portefeuille) public view returns (uint256) {
        Contrepartie memory c = contreparties[_portefeuille];
        return (c.expositionCourante * c.probabiliteDefaut * c.pertesEnCasDefaut) / 10000;
    }

    // Calcul du score de risque
    function calculerScoreDeRisque(address _portefeuille) public view returns (uint256) {
        Contrepartie memory c = contreparties[_portefeuille];
        require(c.estActif, unicode"La contrepartie est inactive.");
        // Exemple de formule : pondération basée sur la probabilité de défaut, les pertes en cas de défaut et le score de crédit
        uint256 score = (100 - c.scoreCredit) + (c.probabiliteDefaut + c.pertesEnCasDefaut) / 2;
        return score;
    }

    // Obtenir contreparties actives
    function obtenirContrepartiesActives() public view returns (address[] memory) {
        uint256 total = toutesLesAdresses.length;
        uint256 count = 0;
        for (uint256 i = 0; i < total; i++) {
            if (contreparties[toutesLesAdresses[i]].estActif) count++;
        }
        address[] memory actives = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < total; i++) {
            if (contreparties[toutesLesAdresses[i]].estActif) {
                actives[index] = toutesLesAdresses[i];
                index++;
            }
        }
        return actives;
    }

    // Statistiques globales
    function consulterStatistiques() public view returns (uint256, uint256, uint256) {
        uint256 totalActives = 0;
        uint256 expositionTotale = 0;
        uint256 couvertureTotale = 0;

        for (uint256 i = 0; i < toutesLesAdresses.length; i++) {
            Contrepartie memory c = contreparties[toutesLesAdresses[i]];
            if (c.estActif) {
                totalActives++;
                expositionTotale += c.expositionCourante;
                if (c.expositionCourante > 0) {
                    couvertureTotale += (c.collateral * 100) / c.expositionCourante;
                }
            }
        }
        uint256 tauxMoyenCouverture = totalActives > 0 ? couvertureTotale / totalActives : 0;
        return (totalActives, expositionTotale, tauxMoyenCouverture);
    }
}
