#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"
THREADS=4

mkdir -p "$OUT"

# Index reference if not already indexed
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF="${OUT}/${SAMPLE}.vcf.gz"

    # Align and sort if BAM doesn't exist
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "${RAW}/${SAMPLE}_1.fq.gz" "${RAW}/${SAMPLE}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # Index BAM if not indexed
    if [ ! -f "$BAI" ]; then
        samtools index "$BAM"
    fi

    # Call variants if VCF doesn't exist
    if [ ! -f "$VCF" ]; then
        lofreq call --vcf -f "$REF" "$BAM" > "${OUT}/${SAMPLE}.vcf"
        bgzip "${OUT}/${SAMPLE}.vcf"
        tabix -p vcf "$VCF"
        rm -f "${OUT}/${SAMPLE}.vcf"
    fi
done

# Create collapsed.tsv if not exists
COLLAPSED="${OUT}/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="${OUT}/${SAMPLE}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t]%INFO/AF\n' "$VCF" | \
            awk -v sample="$SAMPLE" 'BEGIN{OFS="\t"} {
                n = split($4, alts, ",");
                m = split($5, afs, ",");
                for (i=1; i<=n; i++) {
                    af = (m > 0 && i <= m) ? afs[i] : ".";
                    print sample, $1, $2, $3, alts[i], af;
                }
            }' >> "$COLLAPSED"
    done
fi