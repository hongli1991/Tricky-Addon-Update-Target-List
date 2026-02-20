import * as asn1js from 'asn1js';
import * as pkijs from 'pkijs';

/**
 * Replacemet of original keygen, creating openssl compatible keybox via webcrypto
 * original keybox generator via python: https://github.com/LRFP-Team/keyboxGenerator/blob/main/keyboxGenerator_v2.0.py
 * second edition keygen via C++: https://github.com/KOWX712/keygen/blob/master/keygen.cpp
 */

/**
 * Retrieves the crypto engine from pkijs library.
 * @returns {Object|null} The crypto engine instance, or null if unavailable.
 */
function getCryptoEngine() {
    try {
        return pkijs.getCrypto(true);
    } catch {
        return null;
    }
}

/**
 * Checks if key generation is available in the current environment.
 * @returns {boolean} True if key generation is available, false otherwise.
 */
export function isKeygenAvailable() {
    if (typeof btoa !== 'function') return false;
    if (!globalThis.window?.crypto?.subtle) return false;
    return !!getCryptoEngine();
}

/**
 * Converts an ArrayBuffer to PEM format.
 * @param {ArrayBuffer} buffer - The DER-encoded buffer to convert.
 * @param {string} type - The type of key/certificate (e.g., 'EC PRIVATE KEY', 'RSA PRIVATE KEY', 'CERTIFICATE').
 * @returns {string} The PEM-encoded string.
 */
function arrayBufferToPem(buffer, type) {
    const base64 = btoa(String.fromCharCode(...new Uint8Array(buffer)));
    const lines = base64.match(/.{1,64}/g) || [];
    return `-----BEGIN ${type}-----\n${lines.join('\n')}\n-----END ${type}-----`;
}

/**
 * Extracts the private key DER from a PKCS#8 structure.
 * @param {ArrayBuffer} pkcs8Der - The PKCS#8 DER-encoded private key.
 * @returns {ArrayBuffer} The extracted private key DER.
 * @throws {Error} If the PKCS#8 structure is invalid or missing the privateKey OCTET STRING.
 */
function extractPkcs8PrivateKeyDer(pkcs8Der) {
    const pkcs8 = asn1js.fromBER(pkcs8Der);
    if (pkcs8.offset === -1 || !(pkcs8.result instanceof asn1js.Sequence)) {
        throw new Error('Invalid PKCS#8 structure');
    }

    const [, , privateKeyOctet] = pkcs8.result.valueBlock.value;
    if (!(privateKeyOctet instanceof asn1js.OctetString)) {
        throw new Error('PKCS#8 missing privateKey OCTET STRING');
    }

    return privateKeyOctet.getValue();
}

/**
 * Parses a PKCS#8 DER-encoded private key and extracts its components.
 * @param {ArrayBuffer} pkcs8Der - The PKCS#8 DER-encoded private key.
 * @returns {Object} An object containing the algorithmIdentifier and privateKeyOctet.
 * @throws {Error} If the PKCS#8 structure is invalid.
 */
function parsePkcs8(pkcs8Der) {
    const pkcs8 = asn1js.fromBER(pkcs8Der);
    if (pkcs8.offset === -1 || !(pkcs8.result instanceof asn1js.Sequence)) {
        throw new Error('Invalid PKCS#8 structure');
    }

    const [, algorithmIdentifier, privateKeyOctet] = pkcs8.result.valueBlock.value;
    if (!(algorithmIdentifier instanceof asn1js.Sequence) || !(privateKeyOctet instanceof asn1js.OctetString)) {
        throw new Error('Invalid PKCS#8 fields');
    }

    return { algorithmIdentifier, privateKeyOctet };
}

/**
 * Generates an ECDSA key pair using the P-256 curve.
 * @returns {Promise<CryptoKeyPair>} The generated ECDSA key pair.
 * @throws {Error} If the WebCrypto engine is unavailable.
 */
async function generateEcKeyPair() {
    const cryptoEngine = getCryptoEngine();
    if (!cryptoEngine) throw new Error('WebCrypto engine is unavailable');
    const algorithm = pkijs.getAlgorithmParameters('ECDSA', 'generateKey');
    algorithm.algorithm.namedCurve = 'P-256';
    const keyPair = await cryptoEngine.generateKey(algorithm.algorithm, true, algorithm.usages);
    return keyPair;
}

/**
 * Generates an RSA key pair with SHA-256 hash algorithm.
 * @returns {Promise<CryptoKeyPair>} The generated RSA key pair.
 * @throws {Error} If the WebCrypto engine is unavailable.
 */
async function generateRsaKeyPair() {
    const cryptoEngine = getCryptoEngine();
    if (!cryptoEngine) throw new Error('WebCrypto engine is unavailable');
    const algorithm = pkijs.getAlgorithmParameters('RSA-OAEP', 'generateKey');
    algorithm.algorithm.hash = 'SHA-256';
    const keyPair = await cryptoEngine.generateKey(algorithm.algorithm, true, algorithm.usages);
    return keyPair;
}

/**
 * Exports an EC private key to PEM format (ECPrivateKey/SEQUENCE).
 * @param {CryptoKey} privateKey - The EC private key to export.
 * @returns {Promise<string>} The PEM-encoded EC private key.
 * @throws {Error} If the key export fails or the ECPrivateKey structure is invalid.
 */
async function exportEcPrivateKey(privateKey) {
    const exported = await window.crypto.subtle.exportKey('pkcs8', privateKey);
    const { algorithmIdentifier, privateKeyOctet } = parsePkcs8(exported);
    const sec1 = asn1js.fromBER(privateKeyOctet.getValue());
    if (sec1.offset === -1 || !(sec1.result instanceof asn1js.Sequence)) {
        throw new Error('Invalid ECPrivateKey structure');
    }

    const algorithmValues = algorithmIdentifier.valueBlock.value;
    const curveOid = algorithmValues[1];
    const hasParameters = sec1.result.valueBlock.value.some(
        (node) => node instanceof asn1js.Constructed && node.idBlock.tagClass === 3 && node.idBlock.tagNumber === 0
    );

    if (!hasParameters && curveOid instanceof asn1js.ObjectIdentifier) {
        const publicKeyIndex = sec1.result.valueBlock.value.findIndex(
            (node) => node instanceof asn1js.Constructed && node.idBlock.tagClass === 3 && node.idBlock.tagNumber === 1
        );
        const parametersNode = new asn1js.Constructed({
            idBlock: { tagClass: 3, tagNumber: 0 },
            value: [new asn1js.ObjectIdentifier({ value: curveOid.valueBlock.toString() })]
        });

        if (publicKeyIndex >= 0) {
            sec1.result.valueBlock.value.splice(publicKeyIndex, 0, parametersNode);
        } else {
            sec1.result.valueBlock.value.push(parametersNode);
        }
    }

    const sec1Der = sec1.result.toBER(false);
    return arrayBufferToPem(sec1Der, 'EC PRIVATE KEY');
}

/**
 * Exports an RSA private key to PEM format (PKCS#1).
 * @param {CryptoKey} privateKey - The RSA private key to export.
 * @returns {Promise<string>} The PEM-encoded RSA private key.
 * @throws {Error} If the key export fails.
 */
async function exportRsaPrivateKey(privateKey) {
    const exported = await window.crypto.subtle.exportKey('pkcs8', privateKey);
    const pkcs1Der = extractPkcs8PrivateKeyDer(exported);
    return arrayBufferToPem(pkcs1Der, 'RSA PRIVATE KEY');
}

/**
 * Generates a self-signed X.509 certificate.
 * @param {CryptoKey} privateKey - The private key to sign the certificate.
 * @param {CryptoKey} publicKey - The public key to include in the certificate.
 * @returns {Promise<string>} The PEM-encoded X.509 certificate.
 * @throws {Error} If certificate generation or signing fails.
 */
async function generateCertificate(privateKey, publicKey) {
    const publicKeyDer = await window.crypto.subtle.exportKey('spki', publicKey);

    const cert = new pkijs.Certificate();
    cert.version = 0;
    cert.serialNumber = new asn1js.Integer({ value: 1 });

    const now = new Date();
    const tenYearsLater = new Date(now.getTime() + 3650 * 24 * 60 * 60 * 1000);

    cert.notBefore = new pkijs.Time({ type: 0, value: now });
    cert.notAfter = new pkijs.Time({ type: 0, value: tenYearsLater });

    cert.issuer.typesAndValues.push(new pkijs.AttributeTypeAndValue({
        type: '2.5.4.3',
        value: new asn1js.Utf8String({ value: 'Generated' })
    }));

    cert.subject.typesAndValues.push(new pkijs.AttributeTypeAndValue({
        type: '2.5.4.3',
        value: new asn1js.Utf8String({ value: 'Generated' })
    }));

    const publicKeyInfo = pkijs.PublicKeyInfo.fromBER(publicKeyDer);
    cert.subjectPublicKeyInfo = publicKeyInfo;

    await cert.sign(privateKey, 'SHA-256');

    const certDer = cert.toSchema().toBER(false);

    return arrayBufferToPem(certDer, 'CERTIFICATE');
}

/**
 * Generates an Android Attestation Keybox with ECDSA and RSA key pairs.
 * The keybox includes an EC private key with a self-signed certificate and an RSA private key.
 * @returns {Promise<string>} The XML-formatted Android Attestation Keybox.
 * @throws {Error} If key generation or certificate creation fails.
 */
export async function generateUnknownKeybox() {
    const ecKeyPair = await generateEcKeyPair();
    const ecPrivateKeyPem = await exportEcPrivateKey(ecKeyPair.privateKey);
    const certPem = await generateCertificate(ecKeyPair.privateKey, ecKeyPair.publicKey);

    const rsaKeyPair = await generateRsaKeyPair();
    const rsaPrivateKeyPem = await exportRsaPrivateKey(rsaKeyPair.privateKey);

    const keybox = `<?xml version="1.0" encoding="UTF-8"?>
<AndroidAttestation>
    <NumberOfKeyboxes>1</NumberOfKeyboxes>
    <Keybox DeviceID="sw">
        <Key algorithm="ecdsa">
            <PrivateKey format="pem">
${ecPrivateKeyPem.split('\n').map(line => '                ' + line).join('\n')}
            </PrivateKey>
            <CertificateChain>
                <NumberOfCertificates>1</NumberOfCertificates>
                <Certificate format="pem">
${certPem.split('\n').map(line => '                    ' + line).join('\n')}
                </Certificate>
            </CertificateChain>
        </Key>
        <Key algorithm="rsa">
            <PrivateKey format="pem">
${rsaPrivateKeyPem.split('\n').map(line => '                ' + line).join('\n')}
            </PrivateKey>
        </Key>
    </Keybox>
</AndroidAttestation>`;

    return keybox;
}
