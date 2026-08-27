#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# ---- Reference indexing (once) -------------------------------------------------
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.amb" ]]; then
    bwa index "$REF"
fi

# ---- Per-sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
    FASTQ1=data/raw/${sample}_1.fq.gz
    FASTQ2=data/raw/${sample}_2.fq.gz
    BAM=$RESULTS/${sample}.bam
    BAI=$BAM.bai
    VCF=$RESULTS/${sample}.vcf.gz
    VTBI=$VCF.tbi

    # Skip if final VCF and its index already exist and are newer than inputs
    if [[ -f "$VTBI" && "$FASTQ1" -ot "$VTBI" && "$FASTQ2" -ot "$VTBI" ]]; then
        continue
    fi

    # 3. Alignment with bwa mem (pipe to samtools sort)
    samtools sort -@ "$THREADS" -o "$BAM" \
      <(bwa mem -t "$THREADS" \
          -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
          "$REF" "$FASTQ1" "$FASTQ2")

    # 5. Index BAM
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq call-parallel
    TMP_VCF=$RESULTS/${sample}.vcf
    if [[ ! -f "$VCF" || "$TMP_VCF" -ot "$BAI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$TMP_VCF" "$BAM"
        bgzip -c "$TMP_VCF" > "$VCF"
        tabix -p vcf "$VCF"
        rm "$TMP_VCF"
    fi
done

# ---- Collapse step ---------------------------------------------------------------
COLLAPSED=$RESULTS/collapsed.tsv
if [[ ! -f "$COLLAPSED" ]] || \
   find "${SAMPLES[@]}" -type f -newer "$COLLAPSED" | grep .; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            VCF=$RESULTS/${sample}.vcf.gz
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" \
              | while read -r chrom pos ref alt af; do
                  echo -e "${sample}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
                done
        done
    } > "$COLLAPSED"
fi

exit 0