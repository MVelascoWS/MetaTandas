// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Interfaz del contrato de MetaPool
interface IMetaPool {
    function deposit(uint256 amount) external payable;
    function withdraw(uint256 amount) external;
    function getPoolBalance() external view returns (uint256);
}

contract Tanda {
    enum EstadoTanda {
        Abierta,
        Cerrada,
        Pendiente,
        EnProgreso,
        Completada
    }

    struct Miembro {
        address payable direccionMiembro;
        uint256 montoContribucion;
        uint256 ultimaRetirada;
        bool haRetirado;
    }

    struct CicloCompletado {
        uint256 numeroCiclo;
        address[] receptores;
    }

    // Variables de estado públicas
    address public propietario;
    string public nombre;
    string public descripcion;
    EstadoTanda public estadoTanda;
    Miembro[] public miembros;
    uint256 public montoContribucion;
    uint256 public montoPenalizacion;
    uint256 public cicloPago;
    uint256 public cicloActual;
    uint256 public tiempoInicio;
    uint256 public tiempoFinal;
    uint256 public intervaloTiempo;
    address public siguienteReceptor;
    CicloCompletado[] public ciclosCompletados;
    mapping(address => bool) public contribuyentes;
    mapping(address => bool) public direccionesRetiradas;
    bool public faseRetiroIniciada;
    uint256 public siguienteTiempoRetiro;
    uint256 public tiempoInicioRetiro;
    uint256 public maxContribuyentes;
    uint256 public indiceUsuario;

    // Contrato MetaPool al que se realizarán depósitos
    IMetaPool public metaPoolContract;

    // Eventos para registrar actividades importantes
    event EventoUnirseTanda(address indexed usuario);
    event EventoContribuir(address indexed miembro, uint256 monto);
    event EventoRetirar(address indexed miembro, uint256 monto);
    event EventoIniciarFaseRetiro();
    event EventoMontoPenalizacionRetiro(address indexed miembro, uint256 monto);
    event EventoDepositoMetaPool(address indexed miembro, uint256 amount);

    // Modificador para permitir solo al propietario ejecutar una función
    modifier soloPropietario() {
        require(msg.sender == propietario, "No autorizado");
        _;
    }

    // Modificador para verificar si la tanda está abierta
    modifier tandaAbierta() {
        require(estadoTanda == EstadoTanda.Abierta, "La tanda esta cerrada");
        _;
    }

    // Modificador para verificar que un usuario no se haya unido a la tanda
    modifier miembroNoUnido() {
        bool miembroExiste = false;
        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == msg.sender) {
                miembroExiste = true;
                break;
            }
        }
        require(!miembroExiste, "El miembro ya se ha unido");
        _;
    }

    // Modificador para verificar que un usuario se ha unido a la tanda
    modifier miembroUnido() {
        bool miembroExiste = false;
        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == msg.sender) {
                miembroExiste = true;
                break;
            }
        }
        require(miembroExiste, "El miembro no se ha unido");
        _;
    }

    // Modificador para verificar que el número máximo de miembros no se ha alcanzado
    modifier maximoMiembrosNoAlcanzado() {
        require(miembros.length < maxContribuyentes, "Numero maximo de miembros alcanzado");
        _;
    }

    // Modificador para verificar que la contribución es válida
    modifier contribucionValida() {
        require(msg.value == montoContribucion, "Monto de contribucion no valido");
        _;
    }

    // Modificador para verificar que la tanda no ha finalizado
    modifier tandaNoFinalizada() {
        require(block.timestamp < tiempoFinal, "La tanda ha finalizado");
        _;
    }

    // Modificador para verificar que la fase de retiro no ha comenzado
    modifier faseRetiroNoIniciada() {
        require(!faseRetiroIniciada, "La fase de retiro ya ha comenzado");
        _;
    }

    // Modificador para verificar que todos los contribuyentes se han unido a la tanda
    modifier todosLosContribuyentesUnidos() {
        require(miembros.length == maxContribuyentes, "No todos los contribuyentes se han unido");
        _;
    }

    // Modificador para verificar que se ha alcanzado el intervalo de retiro
    modifier intervaloRetiroAlcanzado() {
        require(block.timestamp >= siguienteTiempoRetiro, "No se ha alcanzado el intervalo de retiro");
        _;
    }

    // Modificador para verificar que un usuario es miembro de la tanda
    modifier esMiembro(address direccionMiembroVerificar) {
        bool miembroExiste = false;
        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == direccionMiembroVerificar) {
                miembroExiste = true;
                break;
            }
        }
        require(miembroExiste, "Miembro no encontrado");
        _;
    }

    // Constructor del contrato
    constructor(
        string memory _nombre,
        string memory _descripcion,
        uint256 _montoContribucion,
        uint256 _montoPenalizacion,
        uint256 _cicloPago,
        uint256 _tiempoInicio,
        uint256 _tiempoFinal,
        uint256 _intervaloTiempo,
        uint256 _maxContribuyentes,
        address _metaPoolAddress
    ) {
        propietario = payable(msg.sender);
        nombre = _nombre;
        descripcion = _descripcion;
        estadoTanda = EstadoTanda.Abierta;
        montoContribucion = _montoContribucion;
        montoPenalizacion = _montoPenalizacion;
        cicloPago = _cicloPago;
        tiempoInicio = _tiempoInicio;
        tiempoFinal = _tiempoFinal;
        intervaloTiempo = _intervaloTiempo;
        maxContribuyentes = _maxContribuyentes;
        tiempoInicioRetiro = _tiempoInicio;
        metaPoolContract = IMetaPool(_metaPoolAddress);
    }

    // Función para que un usuario se una a la tanda
    function unirseTanda() external payable soloPropietario tandaAbierta miembroNoUnido maximoMiembrosNoAlcanzado {
        Miembro memory nuevoMiembro;
        nuevoMiembro.direccionMiembro = payable(msg.sender);
        nuevoMiembro.montoContribucion = montoContribucion;
        nuevoMiembro.ultimaRetirada = block.timestamp;
        nuevoMiembro.haRetirado = false;

        miembros.push(nuevoMiembro);

        emit EventoUnirseTanda(msg.sender);

        if (miembros.length == maxContribuyentes) {
            estadoTanda = EstadoTanda.Pendiente;
            siguienteReceptor = miembros[0].direccionMiembro;
            faseRetiroIniciada = true;
            siguienteTiempoRetiro = block.timestamp + intervaloTiempo;
            emit EventoIniciarFaseRetiro();
        }
    }

    // Función para depositar fondos en el contrato MetaPool
    function depositToMetaPool(uint256 amount) external soloPropietario tandaAbierta {
        require(estadoTanda == EstadoTanda.Abierta, "La tanda esta cerrada");
        require(address(this).balance >= amount, "Fondos insuficientes en la tanda");

        // Llama a la función de depósito en el contrato IMetaPool
        metaPoolContract.deposit{value: amount}(amount);

        emit EventoDepositoMetaPool(msg.sender, amount);
    }

    // Función para que un miembro contribuya con su monto de contribución
    function contribuir() external payable miembroUnido tandaAbierta tandaNoFinalizada contribucionValida {
        uint256 miembroIndex = obtenerIndiceMiembro(msg.sender);

        miembros[miembroIndex].ultimaRetirada = block.timestamp;
        emit EventoContribuir(msg.sender, msg.value);
    }

    // Función para obtener el índice de un miembro por su dirección
    function obtenerIndiceMiembro(address direccionMiembro) internal view returns (uint256) {
        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == direccionMiembro) {
                return i;
            }
        }
        revert("Miembro no encontrado");
    }

    // Función para que un miembro retire fondos de la tanda
    function retirar() external miembroUnido tandaAbierta tandaNoFinalizada intervaloRetiroAlcanzado {
        require(direccionesRetiradas[msg.sender] == false, "Ya se ha retirado");
        require(contribuyentes[msg.sender] == true, "No es un contribuyente");

        uint256 totalContribucion = address(this).balance;
        uint256 montoRetiro = (totalContribucion * montoContribucion) / maxContribuyentes;

        require(msg.sender == siguienteReceptor, "No eres el siguiente receptor");
        require(block.timestamp >= siguienteTiempoRetiro, "No se ha alcanzado el intervalo de retiro");

        direccionesRetiradas[msg.sender] = true;

        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == msg.sender) {
                miembros[i].haRetirado = true;
            }
        }

        address payable receptor = payable(msg.sender);
        receptor.transfer(montoRetiro - obtenerMontoPenalizacionRetiro());

        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == siguienteReceptor) {
                siguienteReceptor = miembros[(i + 1) % maxContribuyentes].direccionMiembro;
                siguienteTiempoRetiro += intervaloTiempo;

                if (block.timestamp >= tiempoFinal) {
                    faseRetiroIniciada = false;
                }

                break;
            }
        }

        emit EventoRetirar(msg.sender, montoRetiro);
    }

    // Función para obtener el monto de penalización de retiro actual
    function obtenerMontoPenalizacionRetiro() public view miembroUnido tandaAbierta tandaNoFinalizada intervaloRetiroAlcanzado esMiembro(msg.sender) returns (uint256) {
        uint256 tiempoTranscurrido = block.timestamp - tiempoInicioRetiro;
        uint256 ciclosTranscurridos = tiempoTranscurrido / cicloPago;
        uint256 tiempoPenalizacion = (ciclosTranscurridos + 1) * cicloPago + tiempoInicioRetiro;
        uint256 tiempoLimitePenalizacion = tiempoPenalizacion + intervaloTiempo;
        if (block.timestamp >= tiempoPenalizacion && block.timestamp < tiempoLimitePenalizacion) {
            return montoPenalizacion;
        }
        return 0;
    }

    // Función para aplicar una penalización de retiro
    function penalizacionRetiro() external miembroUnido tandaAbierta tandaNoFinalizada intervaloRetiroAlcanzado esMiembro(msg.sender) {
        uint256 penaltyAmount = obtenerMontoPenalizacionRetiro();
        require(penaltyAmount > 0, "No se aplica una penalizacion de retiro en este momento");

        for (uint i = 0; i < miembros.length; i++) {
            if (miembros[i].direccionMiembro == msg.sender) {
                miembros[i].ultimaRetirada = block.timestamp;

                uint256 totalContribucion = address(this).balance;
                uint256 montoRetiro = (totalContribucion * montoContribucion) / maxContribuyentes;

                direccionesRetiradas[msg.sender] = true;

                payable(msg.sender).transfer(montoRetiro - penaltyAmount);

                for (uint j = 0; j < miembros.length; j++) {
                    if (miembros[j].direccionMiembro == siguienteReceptor) {
                        siguienteReceptor = miembros[(j + 1) % maxContribuyentes].direccionMiembro;
                        siguienteTiempoRetiro += intervaloTiempo;

                        if (block.timestamp >= tiempoFinal) {
                            faseRetiroIniciada = false;
                        }

                        break;
                    }
                }

                emit EventoMontoPenalizacionRetiro(msg.sender, penaltyAmount);
                break;
            }
        }
    }

    // Función para completar un ciclo de pagos
    function completarCiclo() external soloPropietario tandaNoFinalizada {
        address[] memory receptoresCiclo = new address[](maxContribuyentes);
        for (uint i = 0; i < miembros.length; i++) {
            receptoresCiclo[i] = siguienteReceptor;
            for (uint j = 0; j < miembros.length; j++) {
                if (siguienteReceptor == miembros[j].direccionMiembro) {
                    siguienteReceptor = miembros[(j + 1) % maxContribuyentes].direccionMiembro;
                    break;
                }
            }
        }
        CicloCompletado memory cicloCompletado;
        cicloCompletado.numeroCiclo = cicloActual;
        cicloActual++;
        cicloCompletado.receptores = receptoresCiclo;
        ciclosCompletados.push(cicloCompletado);
        tiempoInicioRetiro = block.timestamp;
        faseRetiroIniciada = true;
        siguienteTiempoRetiro = block.timestamp + intervaloTiempo;
    }

    // Función para cerrar la tanda
    function cerrarTanda() external soloPropietario tandaAbierta tandaNoFinalizada {
        tiempoFinal = block.timestamp;
        estadoTanda = EstadoTanda.Cerrada;
    }

    // Función para obtener el saldo actual del contrato
    function obtenerSaldoContrato() public view returns (uint256) {
        return address(this).balance;
    }

    // Función para recibir fondos al contrato
    receive() external payable {
        // Asegura que se puedan recibir fondos al contrato
    }
}
