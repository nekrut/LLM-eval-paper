#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RESULTS_DIR="results"
DATA_RAW="data/raw"
DATA_REF="data/ref"
REF_FASTA="${DATA_REF}/chrM.fa"

mkdir -p "${RESULTS_DIR}"

# Index reference genome if needed
if [[ ! -f "${REF_FASTA}.bwt" ]]; then
    bwa index "${REF_FASTA}"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${DATA_RAW}/${SAMPLE}_1.fq.gz"
    R2="${DATA_RAW}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS_DIR}/${SAMPLE}.bam"
    VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    
    # Skip if sample fully processed
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.bam.bai" && -f "${VCF_GZ}.tbi" ]]; then
        continue
    fi
    
    # Align with BWA
    if [[ ! -f "${BAM}" ]]; then
        bwa mem -t "${THREADS}" "${REF_FASTA}" "${R1}" "${R2}" | \
            samtools view -b | \
            samtools sort -@ "${THREADS}" -o "${BAM}"
    fi
    
    # Index BAM file
    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index "${BAM}"
    fi
    
    # Call variants with LoFreq
    if [[ ! -f "${VCF_GZ}" ]]; then
        lofreq call -f "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" "${BAM}"
        bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    fi
    
    # Index compressed VCF
    if [[ ! -f "${VCF_GZ}.tbi" ]]; then
        tabix -p vcf "${VCF_GZ}"
    fi
done

# Create collapsed variant table
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
if [[ ! -f "${COLLAPSED}" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
            
            gunzip -c "${VCF_GZ}" | awk -v sample="${SAMPLE}" '
                BEGIN { FS="\t" }
                /^#/ { next }
                {
                    chrom = $1
                    pos = $2
                    ref = $4
                    alts_str = $5
                    info = $8
                    
                    # Extract AF from INFO field
                    af = ""
                    n_info = split(info, parts, ";")
                    for (i = 1; i <= n_info; i++) {
                        if (index(parts[i], "AF=") == 1) {
                            af = substr(parts[i], 4)
                            break
                        }
                    }
                    
                    if (af == "") af = "."
                    
                    # Split ALT alleles and corresponding AF values
                    n_alt = split(alts_str, alts, ",")
                    n_af = split(af, afs, ",")
                    
                    for (j = 1; j <= n_alt; j++) {
                        alt = alts[j]
                        alt_af = (j <= n_af) ? afs[j] : "."
                        print sample "\t" chrom "\t" pos "\t" ref "\t" alt "\t" alt_af
                    }
                }
            '
        done
    } > "${COLLAPSED}"
fi